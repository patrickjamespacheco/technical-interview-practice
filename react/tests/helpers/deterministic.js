/**
 * Determinism helpers for the React Playwright suites.
 *
 * The provided mock APIs in problems 01-04 are non-deterministic in two ways:
 *
 *   1. Time. Feeds emit seed data through `setTimeout`, then keep injecting
 *      random records on a 2-2.5 s `setInterval`, and every mock request
 *      resolves after a few hundred milliseconds. Tests that "wait a bit"
 *      race the interval: a row can appear between two `count()` calls.
 *   2. Chance. Every mock write does `Math.random() < p ? reject : resolve`,
 *      so a correct implementation fails its assertion p of the time.
 *
 * Neither can be fixed in the problem stubs - those are the candidate's
 * read-only starting point, and the random failure is behaviour the problem
 * deliberately teaches. So the tests take control of the two inputs instead:
 *
 *   - `page.clock` replaces the page's timers, so no time passes unless a test
 *     asks for it. Seed data arrives because the test advanced 300 ms, not
 *     because the machine was fast enough. The background interval never fires
 *     unless a test advances past it.
 *   - `Math.random` is pinned to a constant chosen by the test, so the
 *     resolve/reject branch is a decision the test makes rather than a coin
 *     flip. Both branches stay reachable - see `RANDOM_SUCCESS`/`RANDOM_FAILURE`.
 *
 * The result: a pass means the implementation is right, and a failure means it
 * is wrong. No retries, no inflated timeouts.
 */

/**
 * Pinned `Math.random` values.
 *
 * The mock failure branches use thresholds of 0.2 (problems 01, 02) and 0.15
 * (problems 03, 04). `RANDOM_SUCCESS` sits above every threshold and
 * `RANDOM_FAILURE` below every threshold, so one pair covers all four
 * problems.
 *
 * `Math.random` is also used to pick indices into the random-record generators
 * (`INCIDENT_TYPES[Math.floor(Math.random() * n)]`). A constant keeps those
 * picks valid and reproducible; the assertions read documented seed data, so
 * nothing depends on the generated records varying.
 */
export const RANDOM_SUCCESS = 0.5
export const RANDOM_FAILURE = 0.0

/** Seed data lands within 300 ms of connect in every feed-based problem. */
export const SEED_EMIT_MS = 300

/** Fixed wall time the page starts at, so rendered timestamps are stable. */
const FIXED_START = new Date('2024-05-01T12:00:00Z')

/**
 * Fake milliseconds allowed to elapse between navigation and the pause.
 *
 * `page.clock.install()` installs fake timers but leaves them ticking with
 * real time; only `pauseAt` stops the clock. The app cannot be loaded under an
 * already-paused clock (React never mounts), so the pause has to happen just
 * after navigation, and this is the grace window that gives the pause command
 * room to arrive.
 *
 * It is also the first term in this per-test time budget, measured from the
 * moment the feed connects:
 *
 *     PAUSE_GRACE_MS 400 + SEED_EMIT_MS 300 + settleRequest 600 = 1300 ms
 *
 * That total stays under the shortest background interval (2000 ms in problem
 * 02, 2500 ms in problem 03), so no test can ever have a random record injected
 * into the list it is asserting on.
 */
const PAUSE_GRACE_MS = 400

/**
 * Install fake timers and a pinned `Math.random`, load the app, and stop time.
 *
 * `Math.random` must be pinned before navigation so it is in place when the
 * page's own scripts run. After this returns, no page timer fires until a test
 * asks for it.
 */
export async function installDeterminism(page, { random = RANDOM_SUCCESS } = {}) {
  await installFakeTimers(page, { random })
  await page.goto('/')
  await pauseClock(page)
}

/**
 * Install fake timers and pin `Math.random`, without navigating.
 *
 * Split out for problem 05, whose tests register their own `page.route`
 * handlers between installation and navigation.
 */
export async function installFakeTimers(page, { random = RANDOM_SUCCESS } = {}) {
  await page.clock.install({ time: FIXED_START })
  await page.addInitScript(value => {
    Math.random = () => value
  }, random)
}

/**
 * Stop the clock, after navigation.
 *
 * Must be called after `goto`: the app cannot load under an already-paused
 * clock. From here on the page's timers only move when a test moves them.
 */
export async function pauseClock(page) {
  const now = await page.evaluate(() => Date.now())
  await page.clock.pauseAt(new Date(now + PAUSE_GRACE_MS))
}

/**
 * Advance far enough for a feed's seed records to be delivered.
 *
 * Waits for the app to have mounted first - the feed is connected from an
 * effect, so advancing before mount would advance an empty timer queue.
 * Depending on whether mount landed before or after the pause, the seed timers
 * are either already flushed or flushed here; both paths end with the full
 * seed set delivered exactly once.
 *
 * React StrictMode connects twice in dev, so the seed records are emitted
 * twice; an implementation keyed by record id absorbs the duplicate.
 */
export async function deliverSeedData(page, heading) {
  await page.getByRole('heading', { name: heading }).waitFor()
  await page.clock.runFor(SEED_EMIT_MS)
}

/**
 * Let a pending mock request settle.
 *
 * The mock latencies are 300-500 ms; 600 ms clears all of them while keeping
 * the per-test budget documented on PAUSE_GRACE_MS under the background
 * interval, so settling a request never smuggles in an extra random record.
 */
export async function settleRequest(page, ms = 600) {
  await page.clock.runFor(ms)
}

/**
 * Advance the page clock by an explicit number of milliseconds.
 *
 * Used by problem 01, where the interval is not background noise but the only
 * event source, so each test states exactly how many emissions it wants.
 */
export async function advanceClock(page, ms) {
  await page.clock.runFor(ms)
}
