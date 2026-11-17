import { createServer } from 'node:http';
import { URL } from 'node:url';

const port = Number(process.env.CAPGO_MAESTRO_PORT ?? 3192);
const dropOnceKeys = new Set();
const pausedTransfers = new Map();

function sendBytes(res, totalBytes, chunkSize = 16 * 1024, delayMs = 0) {
  let sent = 0;
  const chunk = Buffer.alloc(chunkSize, 0x61);

  const writeNext = () => {
    if (res.writableEnded) {
      return;
    }
    const remaining = totalBytes - sent;
    if (remaining <= 0) {
      res.end();
      return;
    }
    const size = Math.min(chunkSize, remaining);
    res.write(chunk.subarray(0, size));
    sent += size;
    if (sent >= totalBytes) {
      res.end();
      return;
    }
    if (delayMs > 0) {
      setTimeout(writeNext, delayMs);
      return;
    }
    writeNext();
  };

  writeNext();
}

const server = createServer((req, res) => {
  const url = new URL(req.url ?? '/', `http://127.0.0.1:${port}`);
  const pathname = url.pathname;

  if (req.method === 'GET' && pathname === '/health') {
    res.writeHead(200, { 'content-type': 'text/plain' });
    res.end('ok');
    return;
  }

  if (req.method === 'POST' && pathname === '/control/reset') {
    dropOnceKeys.clear();
    pausedTransfers.clear();
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end('{"ok":true}');
    return;
  }

  if (req.method === 'POST' && pathname.startsWith('/control/resume/')) {
    const token = pathname.split('/').pop() ?? '';
    const callbacks = pausedTransfers.get(token);
    if (callbacks) {
      for (const resume of callbacks) {
        resume();
      }
      pausedTransfers.delete(token);
    }
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end('{"ok":true}');
    return;
  }


  if (req.method === 'GET' && pathname === '/status/500-empty') {
    res.writeHead(500, { 'content-type': 'text/plain', 'content-length': '0' });
    res.end();
    return;
  }

  const statusMatch = pathname.match(/^\/status\/(\d{3})$/);
  if (req.method === 'GET' && statusMatch) {
    const code = Number(statusMatch[1]);
    if (code === 404) {
      res.writeHead(404, { 'content-type': 'text/plain' });
      res.end('not found');
      return;
    }
    if (code >= 500 && code <= 599) {
      const body = 'server error';
      res.writeHead(code, {
        'content-type': 'text/plain',
        'content-length': String(Buffer.byteLength(body)),
        connection: 'close',
      });
      res.end(body);
      return;
    }
  }

  const bytesMatch = pathname.match(/^\/bytes\/(\d+)$/);
  if (req.method === 'GET' && bytesMatch) {
    const total = Number(bytesMatch[1]);
    res.writeHead(200, {
      'content-type': 'application/octet-stream',
      'content-length': String(total),
    });
    res.end(Buffer.alloc(total, 0x2a));
    return;
  }

  const slowMatch = pathname.match(/^\/slow\/(\d+)$/);
  if (req.method === 'GET' && slowMatch) {
    const total = Number(slowMatch[1]);
    res.writeHead(200, {
      'content-type': 'application/octet-stream',
      'content-length': String(total),
    });
    sendBytes(res, total, 8 * 1024, 40);
    return;
  }

  const recoverableMatch = pathname.match(/^\/recoverable\/(\d+)$/);
  if (req.method === 'GET' && recoverableMatch) {
    const total = Number(recoverableMatch[1]);
    const attemptKey = url.searchParams.get('attemptKey') ?? 'default';
    if (!dropOnceKeys.has(attemptKey)) {
      dropOnceKeys.add(attemptKey);
      res.writeHead(200, {
        'content-type': 'application/octet-stream',
        'content-length': String(total),
      });
      const half = Math.max(1, Math.floor(total / 3));
      res.write(Buffer.alloc(half, 0x33), () => {
        req.socket.destroy();
      });
      return;
    }
    res.writeHead(200, {
      'content-type': 'application/octet-stream',
      'content-length': String(total),
    });
    res.end(Buffer.alloc(total, 0x44));
    return;
  }

  const pauseMatch = pathname.match(/^\/pause-mid\/(\d+)$/);
  if (req.method === 'GET' && pauseMatch) {
    const total = Number(pauseMatch[1]);
    const token = url.searchParams.get('token') ?? 'default';
    res.writeHead(200, {
      'content-type': 'application/octet-stream',
      'content-length': String(total),
    });
    const first = Math.max(1, Math.floor(total / 4));
  let resumed = false;
    const resume = () => {
      if (resumed || res.writableEnded) {
        return;
      }
      resumed = true;
      res.end(Buffer.alloc(total - first, 0x66));
    };
    const waiters = pausedTransfers.get(token) ?? [];
    waiters.push(resume);
    pausedTransfers.set(token, waiters);
    res.write(Buffer.alloc(first, 0x55), () => {
      setTimeout(() => {
        resume();
        pausedTransfers.delete(token);
      }, 8_000);
    });
    return;
  }

  res.writeHead(404, { 'content-type': 'text/plain' });
  res.end('unknown path');
});

server.listen(port, '0.0.0.0', () => {
  process.stdout.write(`fake-download-server listening on ${port}\n`);
});