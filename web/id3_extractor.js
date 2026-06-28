// web/id3_extractor.js
// JavaScript functions for ID3 tag extraction using jsmediatags
// This file is loaded via index.html and provides functions callable from Dart via JS Interop

(function() {
  'use strict';

  // Global namespace for our extractor functions
  window.PlayerVFExtractor = window.PlayerVFExtractor || {};

  /**
   * Extract ID3 metadata from an MP3 File object
   * @param {File} file - The MP3 file to extract metadata from
   * @returns {Promise<Object>} Promise resolving to metadata object
   */
  window.PlayerVFExtractor.extractMetadata = function(file) {
    return new Promise((resolve, reject) => {
      if (!file || !(file instanceof File)) {
        reject(new Error('Invalid file object'));
        return;
      }

      if (!window.jsmediatags) {
        reject(new Error('jsmediatags library not loaded'));
        return;
      }

      // Helper to convert jsmediatags values to strings.
      // jsmediatags returns track/disc as {no:3, of:12}, genre as {name:"Rock"},
      // bpm as a number, etc. We must stringify them for proper JS-Dart interop.
      function _str(v) {
        if (v == null || v === undefined) return '';
        if (typeof v === 'string') return v;
        if (typeof v === 'number') return String(v);
        if (typeof v === 'object') {
          // track/disc: {no:3, of:12} → "3/12"
          if (v.no !== undefined) {
            return v.no + (v.of ? '/' + v.of : '');
          }
          // genre: {name:"Rock", index:17} → "Rock"
          if (v.name !== undefined) return String(v.name);
          // fallback: try toString
          return String(v);
        }
        return String(v);
      }

      window.jsmediatags.read(file, {
        onSuccess: function(tag) {
          try {
            const tags = tag.tags || {};
            const result = {
              title: _str(tags.title),
              artist: _str(tags.artist),
              album: _str(tags.album),
              year: _str(tags.year),
              genre: _str(tags.genre),
              track: _str(tags.track),
              albumArtist: _str(tags.albumArtist),
              composer: _str(tags.composer),
              disc: _str(tags.disc),
              bpm: _str(tags.bpm),
              isrc: _str(tags.isrc),
              lyrics: _str(tags.lyrics),
              performer: _str(tags.performer),
              grouping: _str(tags.grouping),
              publisher: _str(tags.publisher),
              copyright: _str(tags.copyright),
              language: _str(tags.language),
              conductor: _str(tags.conductor),
              remixer: _str(tags.remixer),
              encodedBy: _str(tags.encodedBy),
              mood: _str(tags.mood),
              originalArtist: _str(tags.originalArtist),
              coverArt: null,
              coverArtMimeType: null,
              duration: null,
              error: null
            };

            // Extract cover art (picture)
            if (tags.picture) {
              const picture = tags.picture;
              result.coverArt = _arrayBufferToBase64(picture.data);
              result.coverArtMimeType = picture.format || 'image/jpeg';
            }

            // Try to get duration from TLEN frame or estimate
            if (tags.TLEN) {
              result.duration = parseInt(tags.TLEN, 10);
            }

            resolve(result);
          } catch (e) {
            reject(new Error('Failed to parse tag data: ' + e.message));
          }
        },
        onError: function(error) {
          // jsmediatags errors have info property
          const msg = error.info || error.message || 'Unknown error';
          reject(new Error('jsmediatags error: ' + msg));
        }
      });
    });
  };

  /**
   * Extract only cover art from an MP3 File object (faster for cover-only needs)
   * @param {File} file - The MP3 file
   * @returns {Promise<Object>} Promise resolving to cover art data
   */
  window.PlayerVFExtractor.extractCoverArt = function(file) {
    return new Promise((resolve, reject) => {
      if (!file || !(file instanceof File)) {
        reject(new Error('Invalid file object'));
        return;
      }

      if (!window.jsmediatags) {
        reject(new Error('jsmediatags library not loaded'));
        return;
      }

      window.jsmediatags.read(file, {
        onSuccess: function(tag) {
          try {
            const tags = tag.tags || {};
            if (tags.picture) {
              const picture = tags.picture;
              resolve({
                data: _arrayBufferToBase64(picture.data),
                mimeType: picture.format || 'image/jpeg',
                error: null
              });
            } else {
              resolve({
                data: null,
                mimeType: null,
                error: null
              });
            }
          } catch (e) {
            reject(new Error('Failed to extract cover: ' + e.message));
          }
        },
        onError: function(error) {
          const msg = error.info || error.message || 'Unknown error';
          reject(new Error('jsmediatags error: ' + msg));
        }
      });
    });
  };

  /**
   * Convert Uint8Array/ArrayBuffer to Base64 string
   * @param {Uint8Array|ArrayBuffer} buffer
   * @returns {string} Base64 encoded string
   */
  function _arrayBufferToBase64(buffer) {
    let bytes;
    if (buffer instanceof ArrayBuffer) {
      bytes = new Uint8Array(buffer);
    } else if (buffer instanceof Uint8Array) {
      bytes = buffer;
    } else {
      // Assume array-like
      bytes = new Uint8Array(buffer);
    }

    // Use chunked conversion for large arrays to avoid stack overflow
    const chunkSize = 0x8000; // 32KB chunks
    let binary = '';
    for (let i = 0; i < bytes.length; i += chunkSize) {
      const chunk = bytes.subarray(i, i + chunkSize);
      binary += String.fromCharCode.apply(null, chunk);
    }
    return btoa(binary);
  }

  /**
   * Check if jsmediatags is available
   * @returns {boolean}
   */
  window.PlayerVFExtractor.isAvailable = function() {
    return typeof window.jsmediatags !== 'undefined';
  };

  /**
   * Get library version
   * @returns {string}
   */
  window.PlayerVFExtractor.getVersion = function() {
    return window.jsmediatags?.version || 'unknown';
  };

})();