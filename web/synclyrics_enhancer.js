// web/synclyrics_enhancer.js
// SyncLyrics word-level timing enhancer.
// Takes LRC (line-synced) lyrics and distributes timing to word level.
// NEVER modifies lyrics text — only adjusts timestamps.

(function() {
  'use strict';

  window.SyncLyricsEnhancer = window.SyncLyricsEnhancer || {};

  /**
   * Enhance LRC lyrics with word-level timing.
   * @param {string} lrcText - Standard LRC format lyrics
   * @param {number} totalDuration - Track duration in seconds (optional)
   * @returns {Object} { words: Array<{text, start, end}>, lines: Array }
   */
  window.SyncLyricsEnhancer.enhance = function(lrcText, totalDuration) {
    if (!lrcText || typeof lrcText !== 'string') {
      return { words: [], lines: [] };
    }

    const lines = _parseLrc(lrcText);
    const enhanced = _distributeWords(lines, totalDuration || 0);

    return {
      lines: enhanced.map(function(l) { return { text: l.text, start: l.start, end: l.end, words: l.words }; }),
    };
  };

  /**
   * Convert line-only LRC to word-level by distributing timing evenly.
   */
  function _distributeWords(lines, totalDuration) {
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (line.start == null) continue;

      var wordTexts = line.text.trim().split(/\s+/).filter(function(w) { return w.length > 0; });
      if (wordTexts.length === 0) {
        line.words = [{ text: line.text, start: line.start, end: line.end }];
        continue;
      }

      var nextStart = (i + 1 < lines.length && lines[i + 1].start != null)
          ? lines[i + 1].start
          : (totalDuration > line.start ? totalDuration : line.start + 5.0);

      line.end = nextStart;
      var lineDuration = nextStart - line.start;
      
      // Better Lyrics approach: distribute based on word length
      var totalChars = wordTexts.reduce(function(sum, w) { return sum + w.length; }, 0);
      
      line.words = [];
      var wordStart = line.start;
      for (var w = 0; w < wordTexts.length; w++) {
        var charRatio = totalChars > 0 ? wordTexts[w].length / totalChars : 1 / wordTexts.length;
        var wordDuration = lineDuration * charRatio;
        var wordEnd = wordStart + wordDuration;
        
        line.words.push({
          text: wordTexts[w],
          start: wordStart,
          end: wordEnd
        });
        wordStart = wordEnd;
      }
      
      // Ensure exact end boundary for last word to fix trailing sync issue
      if (line.words.length > 0) {
        line.words[line.words.length - 1].end = nextStart;
      }
    }
    return lines;
  }

  function _parseLrc(lrcText) {
    var lines = [];
    var timeTagRe = /\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]/g;
    var metaRe = /^\[[a-zA-Z]+:.*\]$/;

    var rawLines = lrcText.replace(/\r\n/g, '\n').split('\n');

    for (var i = 0; i < rawLines.length; i++) {
      var line = rawLines[i].trim();
      if (line.length === 0 || metaRe.test(line)) continue;

      var matches = [];
      var match;
      timeTagRe.lastIndex = 0;
      while ((match = timeTagRe.exec(line)) !== null) {
        matches.push(match);
      }

      var text = line.replace(timeTagRe, '').trim();
      if (matches.length === 0) {
        if (text.length > 0) {
          lines.push({ text: text, start: null, end: null, words: [] });
        }
        continue;
      }

      for (var m = 0; m < matches.length; m++) {
        if (text.length === 0) continue;
        var start = _ts(matches[m]);
        var end = start; // Re-calculated later in distribute
        
        lines.push({ text: text, start: start, end: end, words: [] });
      }
    }

    lines.sort(function(a, b) {
      if (a.start == null && b.start == null) return 0;
      if (a.start == null) return 1;
      if (b.start == null) return -1;
      return a.start - b.start;
    });

    return lines;
  }

  function _ts(match) {
    var min = parseInt(match[1], 10) || 0;
    var sec = parseInt(match[2], 10) || 0;
    var frac = match[3] || '0';
    var ms = frac.length === 1 ? parseInt(frac, 10) * 100
         : frac.length === 2 ? parseInt(frac, 10) * 10
         : parseInt(frac.substring(0, 3), 10);
    return min * 60 + sec + ms / 1000;
  }

  /**
   * Check if the enhancer is available.
   */
  window.SyncLyricsEnhancer.isAvailable = function() {
    return true;
  };
})();
