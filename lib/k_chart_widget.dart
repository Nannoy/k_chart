import 'dart:async';

import 'package:flutter/material.dart';
import 'package:k_chart/chart_translations.dart';
import 'package:k_chart/extension/map_ext.dart';
import 'package:k_chart/flutter_k_chart.dart';

enum MainState { MA, BOLL, NONE }

enum SecondaryState { MACD, KDJ, RSI, WR, CCI, NONE }

class TimeFormat {
  static const List<String> YEAR_MONTH_DAY = [yyyy, '-', mm, '-', dd];
  static const List<String> YEAR_MONTH_DAY_WITH_HOUR = [
    yyyy,
    '-',
    mm,
    '-',
    dd,
    ' ',
    HH,
    ':',
    nn
  ];
}

class KChartWidget extends StatefulWidget {
  final List<KLineEntity>? datas;
  final MainState mainState;
  final bool volHidden;
  final SecondaryState secondaryState;
  final Function()? onSecondaryTap;
  final bool isLine;
  final bool isTapShowInfoDialog; //是否开启单击显示详情数据
  final bool hideGrid;
  @Deprecated('Use `translations` instead.')
  final bool isChinese;
  final bool showNowPrice;
  final bool showInfoDialog;
  final bool materialInfoDialog; // Material风格的信息弹窗
  final Map<String, ChartTranslations> translations;
  final List<String> timeFormat;

  //当屏幕滚动到尽头会调用，真为拉到屏幕右侧尽头，假为拉到屏幕左侧尽头
  final Function(bool)? onLoadMore;

  final int fixedLength;
  final List<int> maDayList;
  final int flingTime;
  final double flingRatio;
  final Curve flingCurve;
  final Function(bool)? isOnDrag;
  final ChartColors chartColors;
  final ChartStyle chartStyle;
  final VerticalTextAlignment verticalTextAlignment;
  final bool isTrendLine;
  final double xFrontPadding;

  KChartWidget(
    this.datas,
    this.chartStyle,
    this.chartColors, {
    required this.isTrendLine,
    this.xFrontPadding = 100,
    this.mainState = MainState.MA,
    this.secondaryState = SecondaryState.MACD,
    this.onSecondaryTap,
    this.volHidden = false,
    this.isLine = false,
    this.isTapShowInfoDialog = true,
    this.hideGrid = false,
    @Deprecated('Use `translations` instead.') this.isChinese = false,
    this.showNowPrice = true,
    this.showInfoDialog = true,
    this.materialInfoDialog = true,
    this.translations = kChartTranslations,
    this.timeFormat = TimeFormat.YEAR_MONTH_DAY,
    this.onLoadMore,
    this.fixedLength = 2,
    this.maDayList = const [5, 10, 20],
    this.flingTime = 600,
    this.flingRatio = 0.5,
    this.flingCurve = Curves.decelerate,
    this.isOnDrag,
    this.verticalTextAlignment = VerticalTextAlignment.left,
  });

  @override
  _KChartWidgetState createState() => _KChartWidgetState();
}

class _KChartWidgetState extends State<KChartWidget>
    with TickerProviderStateMixin {
  double mScaleX = 1.0, mScrollX = 0.0, mSelectX = 0.0;
  StreamController<InfoWindowEntity?>? mInfoWindowStream;
  double mHeight = 0, mWidth = 0;
  AnimationController? _controller;
  Animation<double>? aniX;

  //For TrendLine
  List<TrendLine> lines = [];
  double? changeinXposition;
  double? changeinYposition;
  double mSelectY = 0.0;
  bool waitingForOtherPairofCords = false;
  bool enableCordRecord = false;

  double getMinScrollX() {
    return mScaleX;
  }

  double _lastScale = 1.0;
  bool isScale = false, isDrag = false, isLongPress = false, isOnTap = false;
  
  // For tap toggle functionality
  double? _lastTapX;
  double? _lastTapY;
  bool _isInfoVisible = false;
  static const double _tapTolerance = 10.0; // pixels tolerance for same position detection
  
  // For crosshair dragging functionality
  bool _isCrosshairDragging = false;
  double? _dragStartX;
  double? _dragStartY;

  @override
  void initState() {
    super.initState();
    mInfoWindowStream = StreamController<InfoWindowEntity?>();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    mInfoWindowStream?.close();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.datas != null && widget.datas!.isEmpty) {
      mScrollX = mSelectX = 0.0;
      mScaleX = 1.0;
    }
    final _painter = ChartPainter(
      widget.chartStyle,
      widget.chartColors,
      lines: lines, //For TrendLine
      xFrontPadding: widget.xFrontPadding,
      isTrendLine: widget.isTrendLine, //For TrendLine
      selectY: mSelectY, //For TrendLine
      datas: widget.datas,
      scaleX: mScaleX,
      scrollX: mScrollX,
      selectX: mSelectX,
      isLongPass: isLongPress,
      isOnTap: isOnTap,
      isTapShowInfoDialog: widget.isTapShowInfoDialog,
      mainState: widget.mainState,
      volHidden: widget.volHidden,
      secondaryState: widget.secondaryState,
      isLine: widget.isLine,
      hideGrid: widget.hideGrid,
      showNowPrice: widget.showNowPrice,
      sink: mInfoWindowStream?.sink,
      fixedLength: widget.fixedLength,
      maDayList: widget.maDayList,
      verticalTextAlignment: widget.verticalTextAlignment,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        mHeight = constraints.maxHeight;
        mWidth = constraints.maxWidth;

        return ScrollConfiguration(
          behavior: _isCrosshairDragging 
            ? ScrollConfiguration.of(context).copyWith(
                physics: const NeverScrollableScrollPhysics(),
              )
            : ScrollConfiguration.of(context).copyWith(
                physics: const ClampingScrollPhysics(),
              ),
          child: Listener(
        onPointerMove: (event) {
          if (_isCrosshairDragging && _isInfoVisible) {
            // Only update vertical position for vertical-only drags
            final RenderBox box = context.findRenderObject() as RenderBox;
            final localPosition = box.globalToLocal(event.position);
            double newY = localPosition.dy;
            // Clamp to chart bounds
            newY = newY.clamp(widget.chartStyle.topPadding, mHeight - widget.chartStyle.bottomPadding);
            mSelectY = newY;
            notifyChanged();
          }
        },
        child: GestureDetector(
          onTapUp: (details) {
            if (!widget.isTrendLine &&
                widget.onSecondaryTap != null &&
                _painter.isInSecondaryRect(details.localPosition)) {
              widget.onSecondaryTap!();
            }

            if (!widget.isTrendLine &&
                _painter.isInMainRect(details.localPosition)) {
              
              double currentTapX = details.localPosition.dx;
              double currentTapY = details.localPosition.dy;
              
              // Check if this is the same position as last tap
              bool isSamePosition = (_lastTapX != null && 
                                   _lastTapY != null &&
                                   (currentTapX - _lastTapX!).abs() < _tapTolerance && 
                                   (currentTapY - _lastTapY!).abs() < _tapTolerance);
              
              if (isSamePosition && _isInfoVisible) {
                // Toggle off - hide info
                isOnTap = false;
                _isInfoVisible = false;
                _lastTapX = null;
                _lastTapY = null;
                mInfoWindowStream?.sink.add(null);
              } else {
                // Show info at new position
                isOnTap = true;
                _isInfoVisible = true;
                _lastTapX = currentTapX;
                _lastTapY = currentTapY;
                
                if (mSelectX != currentTapX && widget.isTapShowInfoDialog) {
                  mSelectX = currentTapX;
                  mSelectY = currentTapY;
                }
              }
              
              notifyChanged();
            }
            if (widget.isTrendLine && !isLongPress && enableCordRecord) {
              enableCordRecord = false;
              Offset p1 = Offset(getTrendLineX(), mSelectY);
              if (!waitingForOtherPairofCords)
                lines.add(TrendLine(
                    p1, Offset(-1, -1), trendLineMax!, trendLineScale!));

              if (waitingForOtherPairofCords) {
                var a = lines.last;
                lines.removeLast();
                lines.add(TrendLine(a.p1, p1, trendLineMax!, trendLineScale!));
                waitingForOtherPairofCords = false;
              } else {
                waitingForOtherPairofCords = true;
              }
              notifyChanged();
            }
          },

          onScaleStart: (details) {
            _stopAnimation();
            isScale = true;
            
            // Check if we should start crosshair dragging
            if (_isInfoVisible && _painter.isInMainRect(details.localFocalPoint)) {
              _isCrosshairDragging = true;
              _dragStartX = details.localFocalPoint.dx;
              _dragStartY = details.localFocalPoint.dy;
              
              // Immediately update crosshair position for responsive feel
              mSelectX = details.localFocalPoint.dx;
              mSelectY = details.localFocalPoint.dy;
              isOnTap = true;
              _isInfoVisible = true;
              notifyChanged();
            } else {
              // Normal chart scrolling
              _onDragChanged(true);
            }
          },
          onScaleUpdate: (details) {
            if (isLongPress) return;
            
            if (_isCrosshairDragging) {
              // Check if we're still in the main chart area
              if (_painter.isInMainRect(details.localFocalPoint)) {
                // Move crosshair instead of scrolling chart
                double newX = details.localFocalPoint.dx;
                double newY = details.localFocalPoint.dy;
                
                // Clamp to chart bounds
                newX = newX.clamp(0.0, mWidth);
                newY = newY.clamp(widget.chartStyle.topPadding, mHeight - widget.chartStyle.bottomPadding);
                
                mSelectX = newX;
                mSelectY = newY;
                isOnTap = true;
                _isInfoVisible = true;
                notifyChanged();
              } else {
                // Switch to normal scrolling when outside main chart area
                _isCrosshairDragging = false;
                _dragStartX = null;
                _dragStartY = null;
                isOnTap = false;
                _isInfoVisible = false;
                _lastTapX = null;
                _lastTapY = null;
                mInfoWindowStream?.sink.add(null);
                
                // Only scroll if we need more data
                double scrollDelta = details.focalPointDelta.dx / mScaleX;
                if (_shouldScrollForMoreData(scrollDelta)) {
                  mScrollX = (scrollDelta + mScrollX).clamp(0.0, ChartPainter.maxScrollX).toDouble();
                }
                notifyChanged();
              }
            } else {
              // Handle scaling and normal scrolling
              if (details.scale != 1.0) {
                // Scaling operation
                if (_isInfoVisible) {
                  isOnTap = false;
                  _isInfoVisible = false;
                  _lastTapX = null;
                  _lastTapY = null;
                  mInfoWindowStream?.sink.add(null);
                }
                mScaleX = (_lastScale * details.scale).clamp(0.5, 2.2);
              } else {
                // Panning operation (no scaling)
                isOnTap = false;
                _isInfoVisible = false;
                _lastTapX = null;
                _lastTapY = null;
                mInfoWindowStream?.sink.add(null);
                
                // Only scroll if we need more data or if info is not visible
                double scrollDelta = details.focalPointDelta.dx / mScaleX;
                if (!_isInfoVisible || _shouldScrollForMoreData(scrollDelta)) {
                  mScrollX = (scrollDelta + mScrollX).clamp(0.0, ChartPainter.maxScrollX).toDouble();
                }
              }
              notifyChanged();
            }
          },
          onScaleEnd: (details) {
            isScale = false;
            _lastScale = mScaleX;
            
            if (_isCrosshairDragging) {
              // End crosshair dragging
              _isCrosshairDragging = false;
              _dragStartX = null;
              _dragStartY = null;
            } else {
              // Normal chart scrolling with fling
              var velocity = details.velocity.pixelsPerSecond.dx;
              _onFling(velocity);
            }
          },
          onLongPressStart: (details) {
            isOnTap = false;
            isLongPress = true;
            // Only handle trend line creation, not info display
            if (widget.isTrendLine && changeinXposition == null) {
              mSelectX = changeinXposition = details.localPosition.dx;
              mSelectY = changeinYposition = details.globalPosition.dy;
              notifyChanged();
            }
            //For TrendLine
            if (widget.isTrendLine && changeinXposition != null) {
              changeinXposition = details.localPosition.dx;
              changeinYposition = details.globalPosition.dy;
              notifyChanged();
            }
          },
          onLongPressMoveUpdate: (details) {
            // Only handle trend line drawing, not info display
            if (widget.isTrendLine) {
              mSelectX =
                  mSelectX + (details.localPosition.dx - changeinXposition!);
              changeinXposition = details.localPosition.dx;
              mSelectY =
                  mSelectY + (details.globalPosition.dy - changeinYposition!);
              changeinYposition = details.globalPosition.dy;
              notifyChanged();
            }
          },
          onLongPressEnd: (details) {
            isLongPress = false;
            enableCordRecord = true;
            mInfoWindowStream?.sink.add(null);
            notifyChanged();
          },
          child: Stack(
            children: <Widget>[
              CustomPaint(
                size: Size(double.infinity, double.infinity),
                painter: _painter,
              ),
              if (widget.showInfoDialog) _buildInfoDialog()
            ],
          ),
        ),
        ),
      );
    },
    );
  }

  void _stopAnimation({bool needNotify = true}) {
    if (_controller != null && _controller!.isAnimating) {
      _controller!.stop();
      _onDragChanged(false);
      if (needNotify) {
        notifyChanged();
      }
    }
  }

  void _onDragChanged(bool isOnDrag) {
    isDrag = isOnDrag;
    if (widget.isOnDrag != null) {
      widget.isOnDrag!(isDrag);
    }
  }

  void _onFling(double x) {
    _controller = AnimationController(
        duration: Duration(milliseconds: widget.flingTime), vsync: this);
    aniX = null;
    aniX = Tween<double>(begin: mScrollX, end: x * widget.flingRatio + mScrollX)
        .animate(CurvedAnimation(
            parent: _controller!.view, curve: widget.flingCurve));
    aniX!.addListener(() {
      mScrollX = aniX!.value;
      if (mScrollX <= 0) {
        mScrollX = 0;
        if (widget.onLoadMore != null) {
          widget.onLoadMore!(true);
        }
        _stopAnimation();
      } else if (mScrollX >= ChartPainter.maxScrollX) {
        mScrollX = ChartPainter.maxScrollX;
        if (widget.onLoadMore != null) {
          widget.onLoadMore!(false);
        }
        _stopAnimation();
      }
      notifyChanged();
    });
    aniX!.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _onDragChanged(false);
        notifyChanged();
      }
    });
    _controller!.forward();
  }

  void notifyChanged() => setState(() {});
  
  // Check if we need to scroll to show more data
  bool _shouldScrollForMoreData(double scrollDelta) {
    if (scrollDelta > 0 && mScrollX <= 0) {
      // Scrolling right and at left edge - need more historical data
      return true;
    } else if (scrollDelta < 0 && mScrollX >= ChartPainter.maxScrollX) {
      // Scrolling left and at right edge - need more recent data
      return true;
    }
    return false;
  }

  late List<String> infos;

  Widget _buildInfoDialog() {
    return StreamBuilder<InfoWindowEntity?>(
        stream: mInfoWindowStream?.stream,
        builder: (context, snapshot) {
          if ((!isOnTap || !_isInfoVisible) ||
              widget.isLine == true ||
              !snapshot.hasData ||
              snapshot.data?.kLineEntity == null) return Container();
          KLineEntity entity = snapshot.data!.kLineEntity;
          double upDown = entity.change ?? entity.close - entity.open;
          double upDownPercent = entity.ratio ?? (upDown / entity.open) * 100;
          final double? entityAmount = entity.amount;
          infos = [
            getDate(entity.time),
            entity.open.toStringAsFixed(widget.fixedLength),
            entity.high.toStringAsFixed(widget.fixedLength),
            entity.low.toStringAsFixed(widget.fixedLength),
            entity.close.toStringAsFixed(widget.fixedLength),
            "${upDown > 0 ? "+" : ""}${upDown.toStringAsFixed(widget.fixedLength)}",
            "${upDownPercent > 0 ? "+" : ''}${upDownPercent.toStringAsFixed(2)}%",
            if (entityAmount != null) entityAmount.toInt().toString()
          ];
          final dialogPadding = 4.0;
          final dialogWidth = mWidth / 3;
          return Container(
            margin: EdgeInsets.only(
                left: snapshot.data!.isLeft
                    ? dialogPadding
                    : mWidth - dialogWidth - dialogPadding,
                top: 25),
            width: dialogWidth,
            decoration: BoxDecoration(
                color: widget.chartColors.selectFillColor,
                border: Border.all(
                    color: widget.chartColors.selectBorderColor, width: 0.5)),
            child: ListView.builder(
              padding: EdgeInsets.all(dialogPadding),
              itemCount: infos.length,
              itemExtent: 14.0,
              shrinkWrap: true,
              itemBuilder: (context, index) {
                final translations = widget.isChinese
                    ? kChartTranslations['zh_CN']!
                    : widget.translations.of(context);

                return _buildItem(
                  infos[index],
                  translations.byIndex(index),
                );
              },
            ),
          );
        });
  }

  Widget _buildItem(String info, String infoName) {
    Color color = widget.chartColors.infoWindowNormalColor;
    if (info.startsWith("+"))
      color = widget.chartColors.infoWindowUpColor;
    else if (info.startsWith("-")) color = widget.chartColors.infoWindowDnColor;
    final infoWidget = Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
            child: Text("$infoName",
                style: TextStyle(
                    color: widget.chartColors.infoWindowTitleColor,
                    fontSize: 10.0))),
        Text(info, style: TextStyle(color: color, fontSize: 10.0)),
      ],
    );
    return widget.materialInfoDialog
        ? Material(color: Colors.transparent, child: infoWidget)
        : infoWidget;
  }

  String getDate(int? date) => dateFormat(
      DateTime.fromMillisecondsSinceEpoch(
          date ?? DateTime.now().millisecondsSinceEpoch),
      widget.timeFormat);
}
