import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:signals/signals_flutter.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:flowprompt/models/recent_file.dart';
import 'package:flowprompt/signals/prompter_signals.dart';
import 'package:flowprompt/ui/prompter/widgets/prompter_controls.dart';

@RoutePage()
class PrompterScreen extends StatefulWidget {
  const PrompterScreen({super.key});

  @override
  State<PrompterScreen> createState() => _PrompterScreenState();
}

class _PrompterScreenState extends State<PrompterScreen>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _pdfController = PdfViewerController();
  Ticker? _ticker;
  Duration _lastTickTime = Duration.zero;
  Timer? _hideControlsTimer;
  bool _countdownActive = false;
  int _countdownValue = 3;
  final _progress = ValueNotifier<double>(0.0);
  double _pdfScrollY = 0.0;
  int _pdfPageCount = 0;
  bool _userIsTouching = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _ticker!.start();
    WakelockPlus.enable();

    // Enter fullscreen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Start auto-hide timer for controls
    _resetHideControlsTimer();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _scrollController.dispose();
    _pdfController.dispose();
    _hideControlsTimer?.cancel();
    _progress.dispose();
    WakelockPlus.disable();

    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }

  bool get _isPdf => scriptFileType.value == ScriptFileType.pdf;

  void _onTick(Duration elapsed) {
    if (!isScrolling.value || _countdownActive || _userIsTouching) {
      _lastTickTime = elapsed;
      return;
    }

    final dt = (elapsed - _lastTickTime).inMicroseconds / 1000000.0;
    _lastTickTime = elapsed;

    if (_isPdf) {
      _onTickPdf(dt);
    } else {
      _onTickText(dt);
    }
  }

  void _onTickText(double dt) {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;
      final newOffset = currentScroll + scrollSpeed.value * dt;

      if (newOffset >= maxScroll) {
        _scrollController.jumpTo(maxScroll);
        isScrolling.value = false;
        _progress.value = 1.0;
      } else {
        _scrollController.jumpTo(newOffset);
        _progress.value = maxScroll > 0 ? newOffset / maxScroll : 0.0;
      }
    }
  }

  void _onTickPdf(double dt) {
    final prevY = _pdfController.scrollOffset.dy;
    _pdfScrollY += scrollSpeed.value * dt;
    _pdfController.jumpTo(yOffset: _pdfScrollY);

    // Detect end of document: if the viewer didn't actually scroll
    final actualY = _pdfController.scrollOffset.dy;
    if (_pdfScrollY > 0 && (actualY - prevY).abs() < 0.1 && actualY > 0) {
      _pdfScrollY = actualY;
      isScrolling.value = false;
      _progress.value = 1.0;
      return;
    }

    // Update progress based on page number
    if (_pdfPageCount > 0) {
      _progress.value = (_pdfController.pageNumber) / _pdfPageCount;
    }
  }

  void _togglePlayPause() {
    if (!isScrolling.value) {
      _startWithCountdown();
    } else {
      isScrolling.value = false;
    }
  }

  void _startWithCountdown() {
    setState(() {
      _countdownActive = true;
      _countdownValue = 3;
    });

    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdownValue--;
      });
      if (_countdownValue <= 0) {
        timer.cancel();
        setState(() {
          _countdownActive = false;
        });
        isScrolling.value = true;
      }
    });
  }

  void _resetToTop() {
    isScrolling.value = false;
    if (_isPdf) {
      _pdfScrollY = 0.0;
      _pdfController.jumpToPage(1);
      _progress.value = 0.0;
    } else if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      _progress.value = 0.0;
    }
  }

  void _resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    controlsVisible.value = true;
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (isScrolling.value) {
        controlsVisible.value = false;
      }
    });
  }

  void _onPointerDown(PointerDownEvent _) {
    _userIsTouching = true;
  }

  void _onPointerUp(PointerUpEvent _) {
    _userIsTouching = false;
    // Sync auto-scroll position to wherever the user scrolled
    if (_isPdf) {
      _pdfScrollY = _pdfController.scrollOffset.dy;
    }
  }

  void _onPointerCancel(PointerCancelEvent _) {
    _userIsTouching = false;
    if (_isPdf) {
      _pdfScrollY = _pdfController.scrollOffset.dy;
    }
  }

  void _onTapContent() {
    if (!controlsVisible.value) {
      _resetHideControlsTimer();
    } else {
      _togglePlayPause();
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = scriptContent.watch(context);
    final fileName = scriptFileName.watch(context);
    final fileType = scriptFileType.watch(context);
    final currentPdfBytes = pdfBytes.watch(context);
    final currentFontSize = fontSize.watch(context);
    final currentFontFamily = fontFamily.watch(context);
    final dark = isDarkMode.watch(context);
    final showControls = controlsVisible.watch(context);
    final mirrored = isMirrored.watch(context);

    final textColor = dark ? Colors.white : Colors.black;
    final bgColor = dark ? Colors.black : Colors.white;

    final textStyle = GoogleFonts.getFont(
      currentFontFamily,
      fontSize: currentFontSize,
      color: textColor,
      height: 1.6,
    );

    return Theme(
      data: dark ? ThemeData.dark() : ThemeData.light(),
      child: Scaffold(
        backgroundColor: bgColor,
        body: GestureDetector(
          onTap: _onTapContent,
          onPanUpdate: (_) => _resetHideControlsTimer(),
          child: Stack(
            children: [
              // Main content -- wrapped in Listener to detect touch for
              // allowing manual scroll while auto-scrolling
              Listener(
                onPointerDown: _onPointerDown,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(mirrored ? math.pi : 0),
                  child: _buildContent(
                    content,
                    fileType,
                    currentPdfBytes,
                    textStyle,
                    bgColor,
                    textColor,
                  ),
                ),
              ),

              // Progress bar at top
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<double>(
                  valueListenable: _progress,
                  builder: (context, value, _) {
                    return LinearProgressIndicator(
                      value: value,
                      minHeight: 3,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.7),
                      ),
                    );
                  },
                ),
              ),

              // Countdown overlay
              if (_countdownActive)
                Center(
                  child: Text(
                    '$_countdownValue',
                    style: GoogleFonts.robotoSlab(
                      fontSize: 120,
                      fontWeight: FontWeight.bold,
                      color: textColor.withValues(alpha: 0.3),
                    ),
                  ),
                ),

              // Controls overlay
              if (showControls)
                PrompterControls(
                  fileName: fileName,
                  isScrolling: isScrolling.watch(context),
                  onPlayPause: _togglePlayPause,
                  onResetToTop: _resetToTop,
                  onBack: () {
                    resetScript();
                    context.router.maybePop();
                  },
                  onInteraction: _resetHideControlsTimer,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    String content,
    ScriptFileType fileType,
    Uint8List? currentPdfBytes,
    TextStyle textStyle,
    Color bgColor,
    Color textColor,
  ) {
    if (fileType == ScriptFileType.pdf && currentPdfBytes != null) {
      return SfPdfViewer.memory(
        currentPdfBytes,
        controller: _pdfController,
        canShowScrollHead: false,
        canShowScrollStatus: false,
        canShowPaginationDialog: false,
        enableDoubleTapZooming: true,
        enableTextSelection: false,
        pageLayoutMode: PdfPageLayoutMode.continuous,
        scrollDirection: PdfScrollDirection.vertical,
        onDocumentLoaded: (details) {
          _pdfPageCount = details.document.pages.count;
          _pdfScrollY = 0.0;
        },
        onPageChanged: (details) {
          if (_pdfPageCount > 0) {
            _progress.value = details.newPageNumber / _pdfPageCount;
          }
        },
        onTap: (details) {
          _onTapContent();
        },
      );
    }

    if (fileType == ScriptFileType.markdown) {
      return Markdown(
        controller: _scrollController,
        data: content,
        selectable: false,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
        styleSheet: MarkdownStyleSheet(
          p: textStyle,
          h1: textStyle.copyWith(
            fontSize: textStyle.fontSize! * 1.8,
            fontWeight: FontWeight.bold,
          ),
          h2: textStyle.copyWith(
            fontSize: textStyle.fontSize! * 1.5,
            fontWeight: FontWeight.bold,
          ),
          h3: textStyle.copyWith(
            fontSize: textStyle.fontSize! * 1.3,
            fontWeight: FontWeight.bold,
          ),
          h4: textStyle.copyWith(
            fontSize: textStyle.fontSize! * 1.1,
            fontWeight: FontWeight.bold,
          ),
          h5: textStyle.copyWith(fontWeight: FontWeight.bold),
          h6: textStyle.copyWith(
            fontWeight: FontWeight.bold,
            fontStyle: FontStyle.italic,
          ),
          listBullet: textStyle,
          strong: textStyle.copyWith(fontWeight: FontWeight.bold),
          em: textStyle.copyWith(fontStyle: FontStyle.italic),
          blockquotePadding: const EdgeInsets.all(16),
          blockquoteDecoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: textColor.withValues(alpha: 0.3),
                width: 4,
              ),
            ),
          ),
          code: textStyle.copyWith(
            fontFamily: 'monospace',
            fontSize: textStyle.fontSize! * 0.85,
            backgroundColor: textColor.withValues(alpha: 0.1),
          ),
          codeblockDecoration: BoxDecoration(
            color: textColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }

    if (fileType == ScriptFileType.html) {
      // 1. Remove <style> blocks (Google Docs default styles)
      var cleanContent = content.replaceAll(
        RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
        '',
      );

      // 2. Remove all inline 'style="..."' attributes from tags.
      // This forces the content to use our app's font, size, and color settings,
      // while preserving structural tags like <h1>, <b>, <i>, <ul>, etc.
      cleanContent = cleanContent.replaceAll(
        RegExp(r' style="[^"]*"', caseSensitive: false),
        '',
      );

      return SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
        child: HtmlWidget(
          cleanContent,
          textStyle: textStyle,
          // We only need to force transparency on the body/root
          customStylesBuilder: (element) {
            if (element.localName == 'body') {
              return {'background-color': 'transparent'};
            }
            return null;
          },
        ),
      );
    }

    // Plain text
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      child: Text(content, style: textStyle),
    );
  }
}
