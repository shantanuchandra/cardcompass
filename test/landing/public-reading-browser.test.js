import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { spawn } from 'node:child_process';
import { access, mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import net from 'node:net';

const repoRoot = new URL('../../', import.meta.url);
const chromeCandidates = [
  process.env.CHROME_BIN,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
].filter(Boolean);
const publicRoutes = [
  '/',
  '/tools/best-card/',
  '/tools/milestone-tracker/',
  '/tools/movie-offers/',
  '/data-security/',
  '/privacy/',
  '/terms/',
  '/recommendation-disclaimer/',
  '/404.html',
];
const targetViewports = [
  { width: 390, height: 844 },
  { width: 1440, height: 900 },
];

async function availableChrome() {
  for (const candidate of chromeCandidates) {
    try {
      await access(candidate);
      return candidate;
    } catch {
      // Try the next standard Chrome/Chromium location.
    }
  }
  return null;
}

async function unusedPort() {
  const socket = net.createServer();
  socket.listen(0, '127.0.0.1');
  await once(socket, 'listening');
  const { port } = socket.address();
  await new Promise((resolve, reject) => {
    socket.close((error) => error ? reject(error) : resolve());
  });
  return port;
}

function devtoolsWebSocket(child) {
  return new Promise((resolve, reject) => {
    let output = '';
    const timeout = setTimeout(() => {
      reject(new Error(`Chrome did not expose DevTools: ${output}`));
    }, 10_000);

    child.stderr.setEncoding('utf8');
    child.stderr.on('data', (chunk) => {
      output += chunk;
      const match = output.match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (match) {
        clearTimeout(timeout);
        resolve(match[1]);
      }
    });
    child.once('exit', (code) => {
      clearTimeout(timeout);
      reject(new Error(`Chrome exited before DevTools was ready (${code}): ${output}`));
    });
  });
}

async function connectCdp(webSocketUrl) {
  const socket = new WebSocket(webSocketUrl);
  await once(socket, 'open');
  let nextId = 0;
  const pending = new Map();

  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    const request = pending.get(message.id);
    if (!request) return;
    pending.delete(message.id);
    if (message.error) request.reject(new Error(message.error.message));
    else request.resolve(message.result);
  });

  return {
    close: () => socket.close(),
    send(method, params = {}) {
      const id = ++nextId;
      return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
        socket.send(JSON.stringify({ id, method, params }));
      });
    },
  };
}

async function evaluate(cdp, expression) {
  const { result, exceptionDetails } = await cdp.send('Runtime.evaluate', {
    expression,
    returnByValue: true,
    awaitPromise: true,
  });
  if (exceptionDetails) throw new Error(exceptionDetails.text);
  return result.value;
}

let navigationSequence = 0;

async function navigate(cdp, url) {
  const target = new URL(url);
  target.searchParams.set('__browser_test', String(++navigationSequence));
  await cdp.send('Page.navigate', { url: target.href });
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const page = await evaluate(cdp, `({
      readyState: document.readyState,
      href: location.href,
    })`);
    if (page.readyState === 'complete' && page.href === target.href) return;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  throw new Error(`Page did not finish loading: ${target.href}`);
}

async function pressTab(cdp) {
  const key = {
    key: 'Tab',
    code: 'Tab',
    windowsVirtualKeyCode: 9,
    nativeVirtualKeyCode: 9,
  };
  await cdp.send('Input.dispatchKeyEvent', { type: 'rawKeyDown', ...key });
  await cdp.send('Input.dispatchKeyEvent', { type: 'keyUp', ...key });
  for (let attempt = 0; attempt < 40; attempt += 1) {
    const visible = await evaluate(cdp, `(() => {
      const rect = document.activeElement.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.top < innerHeight;
    })()`);
    if (visible) return;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
}

async function clickSelector(cdp, selector) {
  const point = await evaluate(cdp, `(() => {
    const element = document.querySelector(${JSON.stringify(selector)});
    if (!element) return null;
    element.scrollIntoView({ block: 'center', inline: 'center' });
    const rect = element.getBoundingClientRect();
    return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
  })()`);
  if (!point) throw new Error(`Missing click target: ${selector}`);
  await cdp.send('Input.dispatchMouseEvent', {
    type: 'mousePressed',
    button: 'left',
    clickCount: 1,
    ...point,
  });
  await cdp.send('Input.dispatchMouseEvent', {
    type: 'mouseReleased',
    button: 'left',
    clickCount: 1,
    ...point,
  });
  await new Promise((resolve) => setTimeout(resolve, 25));
}

test('public pages render without viewport overflow and expose live keyboard and reduced-motion behavior', { timeout: 45_000 }, async (t) => {
  if (typeof WebSocket === 'undefined') {
    t.skip('This rendered assertion requires a Node runtime with WebSocket support');
    return;
  }
  const chrome = await availableChrome();
  if (!chrome) {
    t.skip('Chrome/Chromium is required for rendered public-page assertions');
    return;
  }

  const serverPort = await unusedPort();
  const server = spawn(process.execPath, ['server.js', String(serverPort)], {
    cwd: repoRoot,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  t.after(() => server.kill());
  await Promise.race([
    once(server.stdout, 'data'),
    new Promise((_, reject) => {
      setTimeout(() => reject(new Error('local server did not start')), 3_000);
    }),
  ]);

  const profile = await mkdtemp(join(tmpdir(), 'cardcompass-chrome-'));
  const chromeProcess = spawn(chrome, [
    '--headless=new',
    '--disable-background-networking',
    '--disable-default-apps',
    '--disable-extensions',
    '--disable-gpu',
    '--no-first-run',
    '--no-sandbox',
    '--remote-debugging-port=0',
    `--user-data-dir=${profile}`,
    'about:blank',
  ], { stdio: ['ignore', 'ignore', 'pipe'] });
  t.after(async () => {
    chromeProcess.kill();
    await rm(profile, { recursive: true, force: true });
  });

  const browserSocket = await devtoolsWebSocket(chromeProcess);
  const devtoolsPort = new URL(browserSocket).port;
  const target = await fetch(
    `http://127.0.0.1:${devtoolsPort}/json/new?${encodeURIComponent('about:blank')}`,
    { method: 'PUT' },
  ).then((response) => response.json());
  const cdp = await connectCdp(target.webSocketDebuggerUrl);
  t.after(() => cdp.close());

  await cdp.send('Page.enable');
  await cdp.send('Runtime.enable');
  await cdp.send('Emulation.setEmulatedMedia', {
    features: [{ name: 'prefers-reduced-motion', value: 'reduce' }],
  });

  for (const viewport of targetViewports) {
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      ...viewport,
      deviceScaleFactor: 1,
      mobile: false,
    });

    for (const route of publicRoutes) {
      await navigate(cdp, `http://127.0.0.1:${serverPort}${route}`);

      const layout = await evaluate(cdp, `(() => ({
        innerWidth: window.innerWidth,
        scrollWidth: document.documentElement.scrollWidth,
        reducedMotion: matchMedia('(prefers-reduced-motion: reduce)').matches,
        scrollBehavior: getComputedStyle(document.documentElement).scrollBehavior,
      }))()`);
      assert.equal(layout.innerWidth, viewport.width, `${route} viewport width`);
      assert.ok(
        layout.scrollWidth <= layout.innerWidth,
        `${route} at ${viewport.width}px must not overflow horizontally`,
      );
      assert.equal(layout.reducedMotion, true, `${route} reduced motion`);
      assert.equal(layout.scrollBehavior, 'auto', `${route} scroll behavior`);

      const visitedFocusStops = new Set();
      let firstFocus;
      let completedTraversal = false;
      for (let focusIndex = 0; focusIndex < 100; focusIndex += 1) {
        await pressTab(cdp);
        const focus = await evaluate(cdp, `(() => {
          const element = document.activeElement;
          const style = getComputedStyle(element);
          const rect = element.getBoundingClientRect();
          return {
            domIndex: [...document.querySelectorAll('*')].indexOf(element),
            tag: element.tagName,
            className: element.className,
            href: element.getAttribute('href'),
            visible: rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.top < innerHeight,
            indicator: style.outlineStyle !== 'none' || style.boxShadow !== 'none',
          };
        })()`);
        if (focus.tag === 'BODY' && firstFocus) continue;
        if (visitedFocusStops.has(focus.domIndex)) {
          assert.equal(
            focus.domIndex,
            firstFocus.domIndex,
            `${route} at ${viewport.width}px: focus repeated before completing the traversal`,
          );
          completedTraversal = true;
          break;
        }
        visitedFocusStops.add(focus.domIndex);
        const focusContext = `${route} at ${viewport.width}px stop ${focusIndex + 1}: ${JSON.stringify(focus)}`;
        assert.equal(focus.visible, true, `${focusContext}: focused control is not visible`);
        assert.equal(focus.indicator, true, `${focusContext}: focused control has no visible indicator`);
        if (focusIndex === 0) firstFocus = focus;
      }
      assert.equal(completedTraversal, true, `${route}: keyboard traversal did not complete within 100 stops`);
      assert.ok(visitedFocusStops.size > 1, `${route}: traversal did not advance beyond one control`);
      if (route !== '/404.html') {
        assert.match(firstFocus.className, /skip-link/, `${route}: skip link is not first`);
        assert.equal(firstFocus.href, '#main', `${route}: skip target changed`);
      }
    }
  }

  for (const viewport of targetViewports) {
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      ...viewport,
      deviceScaleFactor: 1,
      mobile: false,
    });
    await navigate(cdp, `http://127.0.0.1:${serverPort}/`);
    const reducedMotionStart = await evaluate(cdp, `(() => {
      const milliseconds = (value) => value.endsWith('ms')
        ? Number.parseFloat(value)
        : Number.parseFloat(value) * 1000;
      const longest = (value) => Math.max(...value.split(',').map((part) => milliseconds(part.trim())));
      const receiptStyle = getComputedStyle(document.querySelector('.decision-receipt'));
      const buttonStyle = getComputedStyle(document.querySelector('.button'));
      const active = document.querySelector('.scenario-tab[aria-pressed="true"]');
      return {
        scenario: active?.dataset.scenario,
        receiptNumber: document.querySelector('#receiptNumber')?.textContent,
        receiptTransitionMs: longest(receiptStyle.transitionDuration),
        buttonTransitionMs: longest(buttonStyle.transitionDuration),
      };
    })()`);
    assert.deepEqual(reducedMotionStart, {
      scenario: 'groceries',
      receiptNumber: 'CC-0815-01',
      receiptTransitionMs: 0.01,
      buttonTransitionMs: 0.01,
    }, `reduced-motion starting state at ${viewport.width}px`);

    await new Promise((resolve) => setTimeout(resolve, 4_250));
    const scenarioAfterRotationInterval = await evaluate(
      cdp,
      `document.querySelector('.scenario-tab[aria-pressed="true"]')?.dataset.scenario`,
    );
    assert.equal(
      scenarioAfterRotationInterval,
      'groceries',
      `reduced motion must stop automatic rotation beyond four seconds at ${viewport.width}px`,
    );

    await clickSelector(cdp, '.scenario-tab[data-scenario="dining"]');
    const manualScenario = await evaluate(cdp, `(() => ({
      scenario: document.querySelector('.scenario-tab[aria-pressed="true"]')?.dataset.scenario,
      receiptNumber: document.querySelector('#receiptNumber')?.textContent,
      card: document.querySelector('#receiptCard')?.textContent,
      updating: document.querySelector('.decision-receipt')?.classList.contains('is-updating'),
    }))()`);
    assert.deepEqual(manualScenario, {
      scenario: 'dining',
      receiptNumber: 'CC-0815-02',
      card: 'Example Dining Card',
      updating: false,
    }, `reduced-motion manual selection at ${viewport.width}px`);
  }

  await cdp.send('Emulation.setDeviceMetricsOverride', {
    width: 390,
    height: 844,
    deviceScaleFactor: 1,
    mobile: false,
  });
  await navigate(cdp, `http://127.0.0.1:${serverPort}/data-security/`);
  const table = await evaluate(cdp, `(() => {
    const element = document.querySelector('.data-table');
    return {
      overflowX: getComputedStyle(element).overflowX,
      containsWideContent: element.scrollWidth >= element.clientWidth,
    };
  })()`);
  assert.equal(table.overflowX, 'auto');
  assert.equal(table.containsWideContent, true);
});
