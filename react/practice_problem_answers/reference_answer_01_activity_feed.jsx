/**
 * =============================================================================
 * INTERVIEW PROBLEM 3: Live Activity Feed with Filtering & Optimistic Updates
 * Difficulty: Senior Software Engineer | Estimated time: 45-60 min
 * =============================================================================
 *
 * CONTEXT
 * -------
 * You're building the activity feed for a SaaS developer platform — think
 * Stripe's event log, Linear's notification inbox, or Grafana's alert history.
 *
 * The backend pushes events over a persistent connection (simulated below).
 * Users need to filter the feed and acknowledge events inline.
 *
 * A working mock event source and basic styles are provided. Do not modify
 * anything in the "PROVIDED — DO NOT MODIFY" sections.
 *
 * =============================================================================
 *
 * PART 1 — Live event subscription  (~15 min)
 * ─────────────────────────────────────────────
 * Render an <ActivityFeed /> component that:
 *   - Subscribes to `eventSource` on mount and unsubscribes on unmount.
 *   - Displays incoming events in reverse-chronological order (newest on top).
 *   - Each event row shows: timestamp, type badge, actor, and message.
 *   - New events should appear at the top without losing scroll position for
 *     events already in view. (Hint: prepend, don't append.)
 *
 * PART 2 — Client-side filtering  (~15 min)
 * ──────────────────────────────────────────
 * Add filter controls above the feed:
 *   - A dropdown (or set of toggle buttons) for EVENT TYPE
 *     (values: "all" | "deploy" | "alert" | "payment" | "auth")
 *   - A dropdown for STATUS ("all" | "success" | "warning" | "error")
 *
 * Requirements:
 *   - Filtering is purely client-side — all events stay in memory.
 *   - Changing a filter must NOT restart the event subscription.
 *   - Use useMemo (or equivalent) so the filtered list is only recomputed
 *     when events or filter state actually change.
 *
 * PART 3 — Optimistic acknowledgement  (~15 min)
 * ────────────────────────────────────────────────
 * Add an "Ack" button to each unacknowledged event row.
 *
 * When clicked:
 *   1. Immediately mark the event as acknowledged in local state (optimistic).
 *   2. Call `acknowledgeEvent(eventId)` — it returns a Promise that resolves
 *      on success or rejects ~20% of the time to simulate flakiness.
 *   3. On rejection: revert the event to unacknowledged and display an inline
 *      error message on that row ("Failed — try again").
 *   4. While the request is in-flight, the button should show a loading state
 *      and be disabled to prevent double-submission.
 *
 * =============================================================================
 */

import React, { useState, useEffect, useMemo, useRef, useCallback } from "react";

// =============================================================================
// PROVIDED — DO NOT MODIFY
// =============================================================================

const EVENT_TYPES = ["deploy", "alert", "payment", "auth"];
const STATUSES = ["success", "warning", "error"];
const ACTORS = ["ci-bot", "alice@corp.com", "webhooks-service", "billing-worker", "bob@corp.com"];
const MESSAGES = {
  deploy: ["Deployed v2.4.1 to production", "Rollback triggered on staging", "Build pipeline completed"],
  alert:  ["CPU usage exceeded 90%", "Error rate spike detected", "Latency p99 > 2s"],
  payment: ["Invoice #8821 paid", "Subscription renewed", "Payment method declined"],
  auth:   ["API key created", "OAuth token revoked", "Login from new IP"],
};

let _eventId = 1;

/**
 * createEventSource() → { connect, disconnect, subscribe }
 *
 * connect()           — start emitting events (~every 1.5s)
 * disconnect()        — stop emitting
 * subscribe(handler)  — register a handler; returns an unsubscribe function
 *                       handler receives an event object (see shape below)
 *
 * Event shape:
 * {
 *   id:            string,   // unique identifier
 *   type:          string,   // "deploy" | "alert" | "payment" | "auth"
 *   status:        string,   // "success" | "warning" | "error"
 *   actor:         string,   // who/what triggered the event
 *   message:       string,
 *   timestamp:     string,   // ISO 8601
 *   acknowledged:  false,    // always false when emitted
 * }
 */
export function createEventSource() {
  let handlers = [];
  let timerId = null;

  function emit() {
    const type = EVENT_TYPES[Math.floor(Math.random() * EVENT_TYPES.length)];
    const event = {
      id:           `evt-${_eventId++}`,
      type,
      status:       STATUSES[Math.floor(Math.random() * STATUSES.length)],
      actor:        ACTORS[Math.floor(Math.random() * ACTORS.length)],
      message:      MESSAGES[type][Math.floor(Math.random() * MESSAGES[type].length)],
      timestamp:    new Date().toISOString(),
      acknowledged: false,
    };
    handlers.forEach((h) => h(event));
  }

  return {
    connect:    () => { timerId = setInterval(emit, 1500); },
    disconnect: () => { clearInterval(timerId); timerId = null; },
    subscribe:  (handler) => {
      handlers.push(handler);
      return () => { handlers = handlers.filter((h) => h !== handler); };
    },
  };
}

/**
 * acknowledgeEvent(eventId) → Promise<void>
 * Simulates a PATCH /events/:id API call.
 * Resolves after ~400ms. Rejects ~20% of the time.
 */
export function acknowledgeEvent(eventId) {
  return new Promise((resolve, reject) => {
    setTimeout(() => {
      if (Math.random() < 0.2) {
        reject(new Error(`Failed to acknowledge ${eventId}`));
      } else {
        resolve();
      }
    }, 400);
  });
}

// Shared event source instance — import this in your component
export const eventSource = createEventSource();

// =============================================================================
// YOUR WORK STARTS HERE
// =============================================================================

/**
 * STATUS_COLORS and TYPE_LABELS are helpers you may use for styling.
 * Feel free to add your own or ignore these.
 */
const STATUS_COLORS = {
  success: "#22c55e",
  warning: "#f59e0b",
  error:   "#ef4444",
};

const TYPE_LABELS = {
  deploy:  "Deploy",
  alert:   "Alert",
  payment: "Payment",
  auth:    "Auth",
};

// ---------------------------------------------------------------------------
// PART 1 — Implement ActivityFeed
// ---------------------------------------------------------------------------

function FilterBar({ typeFilter, statusFilter, onTypeChange, onStatusChange }) {
  return (
    <div style={{ display: "flex", gap: 12, marginBottom: 16 }}>
      <select
        data-testid="filter-type"
        value={typeFilter}
        onChange={(e) => onTypeChange(e.target.value)}
      >
        <option value="all">all</option>
        {EVENT_TYPES.map((t) => <option key={t} value={t}>{TYPE_LABELS[t]}</option>)}
      </select>
      <select
        data-testid="filter-status"
        value={statusFilter}
        onChange={(e) => onStatusChange(e.target.value)}
      >
        <option value="all">all</option>
        {STATUSES.map((s) => <option key={s} value={s}>{s}</option>)}
      </select>
    </div>
  );
}

function EventRow({ event, pending, error, onAcknowledge }) {
  return (
    <li
      data-testid="event-row"
      className="event-row"
      style={{
        display: "flex",
        gap: 12,
        alignItems: "center",
        padding: "6px 0",
        borderBottom: "1px solid #e2e8f0",
      }}
    >
      <time dateTime={event.timestamp}>{event.timestamp}</time>
      <span
        data-testid="type-badge"
        style={{ color: STATUS_COLORS[event.status], fontWeight: 600 }}
      >
        {TYPE_LABELS[event.type]}
      </span>
      <span>{event.actor}</span>
      <span>{event.message}</span>
      {event.acknowledged ? (
        <span data-testid="acked-label">Acked</span>
      ) : (
        <button data-testid="ack-btn" disabled={pending} onClick={() => onAcknowledge(event.id)}>
          {pending ? "Acking…" : "Ack"}
        </button>
      )}
      {error ? <span data-testid="ack-error" style={{ color: "#ef4444" }}>Failed — try again</span> : null}
    </li>
  );
}

export function ActivityFeed() {
  const [events, setEvents] = useState([]);
  const [typeFilter, setTypeFilter] = useState("all");
  const [statusFilter, setStatusFilter] = useState("all");
  const [pendingIds, setPendingIds] = useState([]);
  const [failedIds, setFailedIds] = useState([]);

  // Part 1: subscribe once. Filter state is deliberately not a dependency, so
  // changing a filter never tears the subscription down.
  useEffect(() => {
    return eventSource.subscribe((event) => {
      // Prepend: newest first, and existing rows keep their position.
      setEvents((prev) => (prev.some((e) => e.id === event.id) ? prev : [event, ...prev]));
    });
  }, []);

  const visible = useMemo(
    () =>
      events
        .filter((e) => typeFilter === "all" || e.type === typeFilter)
        .filter((e) => statusFilter === "all" || e.status === statusFilter),
    [events, typeFilter, statusFilter],
  );

  const setAcknowledged = useCallback((id, value) => {
    setEvents((prev) => prev.map((e) => (e.id === id ? { ...e, acknowledged: value } : e)));
  }, []);

  const onAcknowledge = useCallback(
    (id) => {
      // Optimistic lock: disable the button before awaiting so a second click
      // cannot double-submit.
      setPendingIds((prev) => [...prev, id]);
      setFailedIds((prev) => prev.filter((x) => x !== id));

      acknowledgeEvent(id)
        .then(() => {
          setAcknowledged(id, true);
          setPendingIds((prev) => prev.filter((x) => x !== id));
        })
        .catch(() => {
          setAcknowledged(id, false);
          setPendingIds((prev) => prev.filter((x) => x !== id));
          setFailedIds((prev) => (prev.includes(id) ? prev : [...prev, id]));
        });
    },
    [setAcknowledged],
  );

  return (
    <div style={{ fontFamily: "monospace", maxWidth: 700, margin: "0 auto", padding: 24 }}>
      <h2 style={{ marginBottom: 16 }}>Activity Feed</h2>

      <FilterBar
        typeFilter={typeFilter}
        statusFilter={statusFilter}
        onTypeChange={setTypeFilter}
        onStatusChange={setStatusFilter}
      />

      {events.length === 0 ? (
        <p style={{ color: "#888" }}>No events yet.</p>
      ) : (
        <ul style={{ listStyle: "none", padding: 0 }}>
          {visible.map((event) => (
            <EventRow
              key={event.id}
              event={event}
              pending={pendingIds.includes(event.id)}
              error={failedIds.includes(event.id)}
              onAcknowledge={onAcknowledge}
            />
          ))}
        </ul>
      )}
    </div>
  );
}

export default function App() {
  useEffect(() => {
    eventSource.connect();
    return () => eventSource.disconnect();
  }, []);

  return <ActivityFeed />;
}
