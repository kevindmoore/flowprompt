import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lumberdash/lumberdash.dart';
import 'package:signals/signals_flutter.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:flowprompt/models/recent_file.dart';
import 'package:flowprompt/services/speech_pace_service.dart';
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
  static const _textHorizontalPadding = 32.0;
  static const _minimumTextVerticalPadding = 80.0;
  static const _textTopViewportPaddingFraction = 0.4;
  static const _textBottomViewportPaddingFraction = 0.6;

  final _scrollController = ScrollController();
  final _pdfController = PdfViewerController();
  Ticker? _ticker;
  Duration _lastTickTime = Duration.zero;
  Timer? _hideControlsTimer;
  Timer? _countdownTimer;
  bool _countdownActive = false;
  int _countdownValue = 3;
  final _progress = ValueNotifier<double>(0.0);
  final _speechPace = SpeechPaceService();
  double _pdfScrollY = 0.0;
  int _pdfPageCount = 0;
  bool _userIsTouching = false;
  bool _playbackStarted = false;
  bool _playbackHasStarted = false;
  String? _speechScriptContent;
  final List<GlobalKey> _htmlBlockKeys = [];
  List<int> _htmlBlockWordEnds = const [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _progress.addListener(_syncProgressSignal);
    _scrollController.addListener(_syncTextProgress);
    WakelockPlus.enable();

    // Enter fullscreen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Start auto-hide timer for controls
    _resetHideControlsTimer();

    _speechPace.onSpeechActivity = _resumeScrollingForSpeech;
    _speechPace.onSpeechMatch = _updatePaceForMatchedHtmlBlock;
    _speechPace.updateScript(scriptContent.value);
    unawaited(_enableSpeechFollowByDefault());
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _progress.removeListener(_syncProgressSignal);
    _scrollController.removeListener(_syncTextProgress);
    _scrollController.dispose();
    _pdfController.dispose();
    _hideControlsTimer?.cancel();
    _countdownTimer?.cancel();
    _speechPace.onSpeechActivity = null;
    _speechPace.onSpeechMatch = null;
    _speechPace.dispose();
    _progress.dispose();
    WakelockPlus.disable();

    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }

  bool get _isPdf => scriptFileType.value == ScriptFileType.pdf;

  bool get _isAtTextEnd =>
      !_isPdf &&
      _scrollController.hasClients &&
      _scrollController.position.extentAfter <= 0.5;

  void _resumeScrollingForSpeech() {
    if (!mounted ||
        !_playbackStarted ||
        _countdownActive ||
        _isAtTextEnd ||
        !speechFollowEnabled.value) {
      return;
    }
    if (!isScrolling.value || !(_ticker?.isActive ?? false)) {
      final offset = _scrollController.hasClients
          ? _scrollController.offset
          : -1.0;
      final max = _scrollController.hasClients
          ? _scrollController.position.maxScrollExtent
          : -1.0;
      logMessage(
        'Prompter: speech re-arm, offset=$offset, max=$max',
      );
    }
    isScrolling.value = true;
    if (!(_ticker?.isActive ?? false)) {
      _lastTickTime = Duration.zero;
      _ticker?.start();
    }
  }

  Future<void> _enableSpeechFollowByDefault() async {
    await _speechPace.setEnabled(true, startPaused: true);
  }

  void _syncProgressSignal() {
    currentPrompterProgress.value = _progress.value;
  }

  void _syncTextProgress() {
    if (_isPdf || !_scrollController.hasClients) {
      return;
    }
    final maxScroll = _scrollController.position.maxScrollExtent;
    _progress.value = maxScroll > 0
        ? _scrollController.offset / maxScroll
        : 0.0;
  }

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
      final effectiveSpeed = scrollSpeed.value * speechSpeedMultiplier.value;
      final newOffset = currentScroll + effectiveSpeed * dt;

      if (newOffset >= maxScroll) {
        logMessage(
          'Prompter: reached text end, offset=$currentScroll, max=$maxScroll',
        );
        _scrollController.jumpTo(maxScroll);
        _progress.value = 1.0;
        _stopPlayback();
      } else {
        _scrollController.jumpTo(newOffset);
        _progress.value = maxScroll > 0 ? newOffset / maxScroll : 0.0;
      }
    }
  }

  void _onTickPdf(double dt) {
    final prevY = _pdfController.scrollOffset.dy;
    final effectiveSpeed = scrollSpeed.value * speechSpeedMultiplier.value;
    _pdfScrollY += effectiveSpeed * dt;
    _pdfController.jumpTo(yOffset: _pdfScrollY);

    // Detect end of document: if the viewer didn't actually scroll
    final actualY = _pdfController.scrollOffset.dy;
    if (_pdfScrollY > 0 && (actualY - prevY).abs() < 0.1 && actualY > 0) {
      _pdfScrollY = actualY;
      _progress.value = 1.0;
      _stopPlayback();
      return;
    }

    // Update progress based on page number
    if (_pdfPageCount > 0) {
      _progress.value = (_pdfController.pageNumber) / _pdfPageCount;
    }
  }

  void _togglePlayPause() {
    logMessage(
      'Prompter: play/pause tapped, playback=$_playbackStarted, countdown=$_countdownActive, scrolling=${isScrolling.value}',
    );
    if (_playbackStarted || _countdownActive) {
      _stopPlayback();
      return;
    }
    _startWithCountdown();
  }

  void _toggleSpeechFollow() {
    _resetHideControlsTimer();
    _speechPace.updateScript(scriptContent.value);
    unawaited(
      _speechPace.setEnabled(
        !speechFollowEnabled.value,
        startPaused: !_playbackStarted,
      ),
    );
  }

  void _startWithCountdown() {
    if (_countdownActive || _playbackStarted) {
      return;
    }
    if (_isAtTextEnd || _progress.value >= 1.0) {
      logMessage('Prompter: play ignored at document end');
      return;
    }
    if (_playbackHasStarted) {
      _startPlayback();
      return;
    }

    setState(() {
      _countdownActive = true;
      _countdownValue = 3;
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdownValue--;
      });
      if (_countdownValue <= 0) {
        timer.cancel();
        _countdownTimer = null;
        _startPlayback();
      }
    });
  }

  void _startPlayback() {
    setState(() {
      _countdownActive = false;
      _playbackStarted = true;
      _playbackHasStarted = true;
    });
    _lastTickTime = Duration.zero;
    _ticker?.start();
    unawaited(_speechPace.resume());
    isScrolling.value = true;
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : -1.0;
    final max = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : -1.0;
    logMessage(
      'Prompter: playback started, offset=$offset, max=$max, multiplier=${speechSpeedMultiplier.value}',
    );
  }

  void _stopPlayback() {
    final playbackWasActive = _playbackStarted;
    final countdownWasActive = _countdownActive;
    logMessage(
      'Prompter: stopping playback, playback=$playbackWasActive, countdown=$countdownWasActive, scrolling=${isScrolling.value}',
    );
    _countdownTimer?.cancel();
    _countdownTimer = null;
    isScrolling.value = false;
    _ticker?.stop();
    unawaited(_speechPace.pause());

    if ((playbackWasActive || countdownWasActive) && mounted) {
      setState(() {
        _playbackStarted = false;
        _countdownActive = false;
        _countdownValue = 3;
      });
    } else {
      _playbackStarted = false;
      _countdownActive = false;
    }
  }

  void _resetToTop() {
    _stopPlayback();
    _playbackHasStarted = false;
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

  void _updatePaceForMatchedHtmlBlock(int matchedWordIndex) {
    if (!mounted ||
        !_playbackStarted ||
        scriptFileType.value != ScriptFileType.html ||
        _userIsTouching ||
        _htmlBlockKeys.isEmpty ||
        _htmlBlockWordEnds.isEmpty) {
      return;
    }

    var blockIndex = _htmlBlockWordEnds.indexWhere(
      (wordEnd) => matchedWordIndex < wordEnd,
    );
    if (blockIndex < 0) {
      blockIndex = _htmlBlockWordEnds.length - 1;
    }
    final keyIndex = (blockIndex * _htmlBlockKeys.length /
            _htmlBlockWordEnds.length)
        .floor()
        .clamp(0, _htmlBlockKeys.length - 1);
    final blockContext = _htmlBlockKeys[keyIndex].currentContext;
    final renderObject = blockContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) {
      return;
    }
    final blockWordStart = blockIndex == 0
        ? 0
        : _htmlBlockWordEnds[blockIndex - 1];
    final blockWordEnd = _htmlBlockWordEnds[blockIndex];
    final blockWordCount = math.max(1, blockWordEnd - blockWordStart);
    final wordFraction =
        ((matchedWordIndex - blockWordStart + 0.5) / blockWordCount)
            .clamp(0.0, 1.0);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final blockTop = renderObject.localToGlobal(Offset.zero).dy;
    final matchedTopFraction =
        (blockTop + (renderObject.size.height * wordFraction)) / screenHeight;
    logMessage(
      'Prompter: measured matched HTML position, word=$matchedWordIndex, block=$blockIndex, key=$keyIndex, blockTop=${blockTop / screenHeight}, wordFraction=$wordFraction, matchedTop=$matchedTopFraction',
    );
    _speechPace.adjustForRenderedPosition(matchedTopFraction);
  }

  List<int> _htmlBlockEnds(String html) {
    final blockPattern = RegExp(
      r'<(?:h[1-6]|p|li|blockquote)\b[^>]*>[\s\S]*?</(?:h[1-6]|p|li|blockquote)>',
      caseSensitive: false,
    );
    final tagPattern = RegExp(r'<[^>]*>');
    final wordPattern = RegExp(r"[A-Za-z0-9']+");

    return [
      for (final match in blockPattern.allMatches(html))
        wordPattern
            .allMatches(html.substring(0, match.end).replaceAll(tagPattern, ' '))
            .length,
    ];
  }

  void _onTapContent() {
    if (!controlsVisible.value) {
      _resetHideControlsTimer();
    } else {
      _togglePlayPause();
    }
  }

  EdgeInsets _textContentPadding(
    BoxConstraints constraints, {
    bool compactTop = false,
  }) {
    final topPadding = compactTop
        ? _minimumTextVerticalPadding
        : math.max(
            _minimumTextVerticalPadding,
            constraints.maxHeight * _textTopViewportPaddingFraction,
          );
    final bottomPadding = math.max(
      _minimumTextVerticalPadding,
      constraints.maxHeight * _textBottomViewportPaddingFraction,
    );

    return EdgeInsets.fromLTRB(
      _textHorizontalPadding,
      topPadding,
      _textHorizontalPadding,
      bottomPadding,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final content = scriptContent.value;
        final fileName = scriptFileName.value;
        final fileType = scriptFileType.value;
        final currentPdfBytes = pdfBytes.value;
        final currentFontSize = fontSize.value;
        final currentFontFamily = fontFamily.value;
        final dark = isDarkMode.value;
        final showControls = controlsVisible.value;
        final mirrored = isMirrored.value;
        final scrolling = isScrolling.value;
        final speechEnabled = speechFollowEnabled.value;
        final speechIsListening = speechListening.value;
        final speechColor = speechIsListening
            ? Colors.greenAccent
            : Colors.redAccent;

        if (_speechScriptContent != content) {
          _speechScriptContent = content;
          _speechPace.updateScript(content);
        }

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
                      isScrolling: scrolling || _countdownActive,
                      onPlayPause: _togglePlayPause,
                      onResetToTop: _resetToTop,
                      speechEnabled: speechEnabled,
                      speechActive: _playbackStarted,
                      speechListening: speechIsListening,
                      onToggleSpeech: _toggleSpeechFollow,
                      onBack: () {
                        _speechPace.setEnabled(false);
                        resetScript();
                        context.router.maybePop();
                      },
                      onInteraction: _resetHideControlsTimer,
                    ),

                  if (speechEnabled && _playbackStarted && !showControls)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: SafeArea(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              speechIsListening ? Icons.mic : Icons.mic_none,
                              color: speechColor,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
      return LayoutBuilder(
        builder: (context, constraints) {
          return Markdown(
            controller: _scrollController,
            data: content,
            selectable: false,
            padding: _textContentPadding(constraints),
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
        },
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
      _htmlBlockWordEnds = _htmlBlockEnds(cleanContent);

      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            controller: _scrollController,
            padding: _textContentPadding(constraints, compactTop: true),
            child: HtmlWidget(
              cleanContent,
              factoryBuilder: () => _TrackedHtmlWidgetFactory(
                _htmlBlockKeys,
              ),
              textStyle: textStyle,
              // We only need to force transparency on the body/root
              customStylesBuilder: (element) {
                if (element.localName == 'body') {
                  return {'background-color': 'transparent'};
                }
                if (element.localName == 'h1') {
                  return {'font-size': '1.25em', 'line-height': '1.4'};
                }
                return null;
              },
            ),
          );
        },
      );
    }

    // Plain text
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _scrollController,
          padding: _textContentPadding(constraints),
          child: Text(content, style: textStyle),
        );
      },
    );
  }
}

class _TrackedHtmlWidgetFactory extends WidgetFactory {
  _TrackedHtmlWidgetFactory(this.blockKeys);

  final List<GlobalKey> blockKeys;

  @override
  Widget buildBodyWidget(BuildContext context, Widget child) {
    final body = super.buildBodyWidget(context, child);
    if (body is! Column) {
      if (blockKeys.isEmpty) {
        blockKeys.add(GlobalKey());
      }
      return KeyedSubtree(key: blockKeys.first, child: body);
    }

    while (blockKeys.length < body.children.length) {
      blockKeys.add(GlobalKey());
    }

    return Column(
      key: body.key,
      mainAxisAlignment: body.mainAxisAlignment,
      mainAxisSize: body.mainAxisSize,
      crossAxisAlignment: body.crossAxisAlignment,
      textDirection: body.textDirection,
      verticalDirection: body.verticalDirection,
      textBaseline: body.textBaseline,
      spacing: body.spacing,
      children: [
        for (var i = 0; i < body.children.length; i++)
          KeyedSubtree(key: blockKeys[i], child: body.children[i]),
      ],
    );
  }
}
