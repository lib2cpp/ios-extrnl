// content.js — основной скрипт, читает доску chess.com и рисует стрелки

(function () {
  "use strict";

  // ── Состояние ──────────────────────────────────────────
  let enabled = true;
  let skillLevel = 10;
  let stockfish = null;
  let sfReady = false;
  let lastFen = "";
  let arrowCanvas = null;
  let resizeObserver = null;
  let pendingAnalysis = false;
  let initTimeout = null;

  // ── Загрузка настроек ──────────────────────────────────
  chrome.runtime.sendMessage({ type: "GET_SETTINGS" }, (res) => {
    if (res) {
      enabled = res.enabled;
      skillLevel = res.level;
    }
    initStockfish();
  });

  chrome.runtime.onMessage.addListener((msg) => {
    if (msg.type === "SETTINGS_CHANGED") {
      enabled = msg.enabled;
      skillLevel = msg.level;
      if (!enabled) clearArrow();
      else analyzePosition();
    }
  });

  // ── Инициализация Stockfish ────────────────────────────
  function initStockfish() {
    try {
      const sfUrl = chrome.runtime.getURL("stockfish/stockfish.js");
      stockfish = new Worker(sfUrl);

      stockfish.onmessage = (e) => {
        const line = e.data;
        if (line === "readyok") {
          sfReady = true;
          setSkillLevel(skillLevel);
          startBoardObserver();
          analyzePosition();
        }
        handleStockfishOutput(line);
      };

      stockfish.onerror = (e) => {
        console.warn("[ChessBot] Stockfish worker error:", e);
      };

      stockfish.postMessage("uci");
      stockfish.postMessage("isready");
    } catch (e) {
      console.warn("[ChessBot] Failed to load Stockfish:", e);
    }
  }

  function setSkillLevel(level) {
    if (!stockfish || !sfReady) return;
    const elo = Math.round(500 + level * 100);
    stockfish.postMessage(`setoption name Skill Level value ${level}`);
    stockfish.postMessage(`setoption name UCI_LimitStrength value true`);
    stockfish.postMessage(`setoption name UCI_Elo value ${elo}`);
  }

  // ── Парсинг хода Stockfish ─────────────────────────────
  let bestMove = null;

  function handleStockfishOutput(line) {
    if (line.startsWith("bestmove")) {
      const parts = line.split(" ");
      bestMove = parts[1] && parts[1] !== "(none)" ? parts[1] : null;
      if (bestMove) drawArrow(bestMove);
      else clearArrow();
      pendingAnalysis = false;
    }
  }

  // ── Наблюдатель за доской ──────────────────────────────
  function startBoardObserver() {
    const observer = new MutationObserver(debounce(onBoardChange, 300));
    const target = document.body;
    observer.observe(target, { childList: true, subtree: true, attributes: true });
    onBoardChange();
  }

  function onBoardChange() {
    if (!enabled) return;
    const fen = getFenFromBoard();
    if (fen && fen !== lastFen) {
      lastFen = fen;
      analyzePosition();
    }
  }

  function analyzePosition() {
    if (!sfReady || !enabled) return;
    const fen = getFenFromBoard();
    if (!fen) return;
    pendingAnalysis = true;
    stockfish.postMessage("stop");
    stockfish.postMessage(`position fen ${fen}`);
    stockfish.postMessage(`go movetime 800`);
  }

  // ── Чтение позиции с доски chess.com ──────────────────
  function getFenFromBoard() {
    try {
      // Метод 1: React внутренние данные
      const boardEl =
        document.querySelector("chess-board") ||
        document.querySelector(".board") ||
        document.querySelector("[class*='board']");

      if (!boardEl) return null;

      // Попытка через window.chessboard
      if (window.chessboard && window.chessboard.game) {
        const game = window.chessboard.game;
        if (game.getFEN) return game.getFEN();
      }

      // Метод 2: читаем фигуры из DOM
      return fenFromDom(boardEl);
    } catch (e) {
      return null;
    }
  }

  function fenFromDom(boardEl) {
    // chess.com использует классы вида "piece wp sq-e2"
    // или piece-{type}{color} на позиции square-{col}{row}
    const pieces = boardEl.querySelectorAll("[class*='piece']");
    if (!pieces.length) return null;

    const grid = {};
    let playerColor = "w"; // определим по позиции короля

    pieces.forEach((p) => {
      const cls = p.className || "";
      // Пример класса: "piece wk square-51" или "piece bp square-74"
      const squareMatch = cls.match(/square-(\d)(\d)/);
      const pieceMatch = cls.match(/\b([wb])([prnbqk])\b/i);

      if (!squareMatch || !pieceMatch) return;

      const col = parseInt(squareMatch[1]); // 1-8 (файл)
      const row = parseInt(squareMatch[2]); // 1-8 (ранг)
      const color = pieceMatch[1].toLowerCase();
      const type = pieceMatch[2].toLowerCase();

      const file = String.fromCharCode(96 + col); // a-h
      const rank = row;
      grid[`${file}${rank}`] = { color, type };
    });

    if (!Object.keys(grid).length) return null;

    // Определяем чья очередь — ищем последний ход
    let turn = detectTurn();

    return buildFen(grid, turn);
  }

  function detectTurn() {
    // Попытка найти индикатор хода на странице
    const clockActive = document.querySelector(
      ".clock-component.clock-player-turn, [class*='clock'][class*='active']"
    );
    if (clockActive) {
      const isBottom =
        clockActive.closest("[class*='bottom'], [class*='player-bottom']") !== null;
      return isBottom ? "w" : "b";
    }
    return "w"; // fallback
  }

  function buildFen(grid, turn) {
    let fen = "";
    for (let rank = 8; rank >= 1; rank--) {
      let empty = 0;
      for (let fileCode = 97; fileCode <= 104; fileCode++) {
        const sq = `${String.fromCharCode(fileCode)}${rank}`;
        const p = grid[sq];
        if (p) {
          if (empty) { fen += empty; empty = 0; }
          const sym = p.color === "w" ? p.type.toUpperCase() : p.type;
          fen += sym;
        } else {
          empty++;
        }
      }
      if (empty) fen += empty;
      if (rank > 1) fen += "/";
    }
    fen += ` ${turn} KQkq - 0 1`;
    return fen;
  }

  // ── Стрелка ────────────────────────────────────────────
  function getOrCreateCanvas(boardEl) {
    if (arrowCanvas && arrowCanvas.parentNode) return arrowCanvas;

    arrowCanvas = document.createElement("canvas");
    arrowCanvas.id = "chessbot-arrow-canvas";
    arrowCanvas.style.cssText = `
      position: absolute;
      top: 0; left: 0;
      width: 100%; height: 100%;
      pointer-events: none;
      z-index: 9999;
    `;

    const container = boardEl.parentElement || boardEl;
    const style = getComputedStyle(container);
    if (style.position === "static") container.style.position = "relative";
    container.appendChild(arrowCanvas);

    return arrowCanvas;
  }

  function drawArrow(move) {
    if (!move || move.length < 4) return;

    const boardEl =
      document.querySelector("chess-board") ||
      document.querySelector(".board");
    if (!boardEl) return;

    const rect = boardEl.getBoundingClientRect();
    const canvas = getOrCreateCanvas(boardEl);
    canvas.width = rect.width;
    canvas.height = rect.height;

    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    const from = move.slice(0, 2); // e.g. "e2"
    const to   = move.slice(2, 4); // e.g. "e4"

    const [fx, fy] = squareToXY(from, rect.width, rect.height);
    const [tx, ty] = squareToXY(to,   rect.width, rect.height);

    drawArrowOnCanvas(ctx, fx, fy, tx, ty, rect.width / 8);
  }

  function squareToXY(sq, w, h) {
    const file = sq.charCodeAt(0) - 97; // a=0 .. h=7
    const rank = parseInt(sq[1]) - 1;   // 1=0 .. 8=7
    const cellW = w / 8;
    const cellH = h / 8;

    // chess.com: белые снизу по умолчанию
    const x = (file + 0.5) * cellW;
    const y = (7 - rank + 0.5) * cellH;
    return [x, y];
  }

  function drawArrowOnCanvas(ctx, x1, y1, x2, y2, cellSize) {
    const headLen = cellSize * 0.38;
    const lineWidth = cellSize * 0.18;
    const angle = Math.atan2(y2 - y1, x2 - x1);

    // Укоротим линию чтобы не перекрывать голову
    const ex = x2 - Math.cos(angle) * headLen * 0.5;
    const ey = y2 - Math.sin(angle) * headLen * 0.5;

    ctx.save();
    ctx.globalAlpha = 0.82;
    ctx.strokeStyle = "#c8a020";
    ctx.fillStyle   = "#c8a020";
    ctx.lineWidth   = lineWidth;
    ctx.lineCap     = "round";

    // Линия
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.lineTo(ex, ey);
    ctx.stroke();

    // Голова стрелки
    ctx.beginPath();
    ctx.moveTo(x2, y2);
    ctx.lineTo(
      x2 - headLen * Math.cos(angle - Math.PI / 6),
      y2 - headLen * Math.sin(angle - Math.PI / 6)
    );
    ctx.lineTo(
      x2 - headLen * Math.cos(angle + Math.PI / 6),
      y2 - headLen * Math.sin(angle + Math.PI / 6)
    );
    ctx.closePath();
    ctx.fill();

    ctx.restore();
  }

  function clearArrow() {
    if (arrowCanvas) {
      const ctx = arrowCanvas.getContext("2d");
      ctx.clearRect(0, 0, arrowCanvas.width, arrowCanvas.height);
    }
  }

  // ── Утилиты ────────────────────────────────────────────
  function debounce(fn, ms) {
    let t;
    return (...args) => {
      clearTimeout(t);
      t = setTimeout(() => fn(...args), ms);
    };
  }
})();
