/**
 * =============================================================================
 * INTERVIEW PROBLEM 2: Real-Time Incident Dashboard
 * Difficulty: Senior Software Engineer | Estimated time: 45–60 min
 * =============================================================================
 *
 * CONTEXT
 * -------
 * You're building the live incident monitoring panel for a public safety
 * operations platform. Incidents are streamed in real time from multiple field
 * sensors and radio dispatch sources. Operators need to see active incidents
 * sorted by recency, filter by severity/type, and mark incidents as contained.
 *
 * A working mock incident feed, sample data, and basic styles are provided.
 * Do NOT modify anything in the "PROVIDED — DO NOT MODIFY" sections.
 *
 * =============================================================================
 *
 * PART 1 — Live incident feed  (~15 min)
 * ───────────────────────────────────────
 * Render an <IncidentDashboard /> component that:
 *   - Subscribes to `incidentFeed` on mount and unsubscribes on unmount.
 *   - Displays active (uncontained) incidents, newest first.
 *   - Each row shows: severity badge (color-coded), incident type, location,
 *     and a relative timestamp ("2 min ago").
 *
 * Data-testid requirements (Playwright relies on these):
 *   data-testid="incident-row"    — wrapper element for each active incident
 *   data-testid="severity-badge"  — the colored severity indicator in each row
 *
 * PART 2 — Filtering  (~15 min)
 * ──────────────────────────────
 * Add filter controls above the incident list:
 *   - A <select data-testid="filter-severity"> for severity
 *     (options: "all", "critical", "high", "medium", "low")
 *   - A <select data-testid="filter-type"> for incident type
 *     (options: "all" + each value in INCIDENT_TYPES)
 *
 * Requirements:
 *   - Filtering is purely client-side — all incidents stay in memory.
 *   - Changing a filter must NOT restart the feed subscription.
 *   - Use useMemo (or equivalent) so the filtered list is only recomputed
 *     when incidents or filter state actually change.
 *   - Show a count of currently visible incidents next to the filters.
 *
 * PART 3 — Optimistic "Contain" action  (~15 min)
 * ─────────────────────────────────────────────────
 * Add a "Contain" button to each active incident row.
 *
 * When clicked:
 *   1. Immediately mark the incident as contained in local state (optimistic).
 *   2. Call `containIncident(incidentId)` — resolves on success, rejects ~20%.
 *   3. On success: move the row to a "Contained" section at the bottom of the
 *      page with data-testid="contained-row".
 *   4. On rejection: revert the incident to active, show an inline error
 *      ("Failed — retry") on that row.
 *   5. While the request is in-flight, the button (data-testid="contain-btn")
 *      must be disabled to prevent double-submission.
 *
 * =============================================================================
 */

import React, { useState, useEffect, useMemo, useCallback } from 'react'

// =============================================================================
// PROVIDED — DO NOT MODIFY
// =============================================================================

export const INCIDENT_TYPES = ['shooting', 'car-crash', 'fire', 'break-in', 'flooding']
export const SEVERITIES     = ['critical', 'high', 'medium', 'low']
export const LOCATIONS      = [
  'Downtown', 'Midtown', 'Eastside', 'Westside', 'South Bay',
  'Harbor District', 'North Hills', 'Riverfront',
]

export const SEVERITY_COLORS = {
  critical: { background: '#fef2f2', color: '#991b1b', border: '#fca5a5' },
  high:     { background: '#fff7ed', color: '#9a3412', border: '#fdba74' },
  medium:   { background: '#fefce8', color: '#854d0e', border: '#fde047' },
  low:      { background: '#f0fdf4', color: '#166534', border: '#86efac' },
}

/**
 * Deterministic seed incidents — appear immediately on connect.
 * Playwright tests rely on the location names and severities here.
 */
export const SEED_INCIDENTS = [
  { id: 'inc-s1', type: 'shooting',  severity: 'critical', location: 'Downtown',       ts: new Date(Date.now() - 2  * 60_000).toISOString(), contained: false },
  { id: 'inc-s2', type: 'car-crash', severity: 'high',     location: 'Midtown',        ts: new Date(Date.now() - 5  * 60_000).toISOString(), contained: false },
  { id: 'inc-s3', type: 'fire',      severity: 'critical', location: 'Eastside',       ts: new Date(Date.now() - 8  * 60_000).toISOString(), contained: false },
  { id: 'inc-s4', type: 'break-in',  severity: 'medium',   location: 'Westside',       ts: new Date(Date.now() - 12 * 60_000).toISOString(), contained: false },
  { id: 'inc-s5', type: 'flooding',  severity: 'low',      location: 'South Bay',      ts: new Date(Date.now() - 20 * 60_000).toISOString(), contained: false },
]

let _incidentId = 100

function makeRandomIncident() {
  const type     = INCIDENT_TYPES[Math.floor(Math.random() * INCIDENT_TYPES.length)]
  const severity = SEVERITIES[Math.floor(Math.random() * SEVERITIES.length)]
  const location = LOCATIONS[Math.floor(Math.random() * LOCATIONS.length)]
  return {
    id:        `inc-${_incidentId++}`,
    type,
    severity,
    location,
    ts:        new Date().toISOString(),
    contained: false,
  }
}

/**
 * createIncidentFeed() → { connect, disconnect, subscribe }
 *
 * connect()           — start emitting; seed incidents arrive within 300ms,
 *                       then a new random incident every 2s
 * disconnect()        — stop emitting
 * subscribe(handler)  — handler receives an incident object; returns unsubscribe fn
 */
export function createIncidentFeed() {
  let handlers = []
  let timerId  = null

  function emit(incident) {
    handlers.forEach(h => h({ ...incident }))
  }

  return {
    connect() {
      // Emit seed incidents quickly for deterministic Playwright tests
      SEED_INCIDENTS.forEach((inc, i) => setTimeout(() => emit(inc), i * 50))
      // Then keep emitting random incidents
      timerId = setInterval(() => emit(makeRandomIncident()), 2000)
    },
    disconnect() {
      clearInterval(timerId)
      timerId = null
    },
    subscribe(handler) {
      handlers.push(handler)
      return () => { handlers = handlers.filter(h => h !== handler) }
    },
  }
}

/**
 * containIncident(incidentId) → Promise<void>
 * Simulates a PATCH /incidents/:id API call.
 * Resolves after ~500ms. Rejects ~20% of the time.
 */
export function containIncident(incidentId) {
  return new Promise((resolve, reject) => {
    setTimeout(() => {
      Math.random() < 0.2
        ? reject(new Error(`Failed to contain ${incidentId}`))
        : resolve()
    }, 500)
  })
}

// Shared singleton — import this in your component
export const incidentFeed = createIncidentFeed()

// =============================================================================
// YOUR WORK STARTS HERE
// =============================================================================

/**
 * SEVERITY_COLORS and INCIDENT_TYPES are available above for styling.
 * Feel free to add helpers or sub-components as needed.
 */

// ---------------------------------------------------------------------------
// PART 1 — Implement IncidentDashboard
// ---------------------------------------------------------------------------

function relativeTime(ts) {
  const mins = Math.max(0, Math.round((Date.now() - new Date(ts).getTime()) / 60_000))
  if (mins < 1) return 'just now'
  return `${mins} min ago`
}

function SeverityBadge({ severity }) {
  const palette = SEVERITY_COLORS[severity] ?? SEVERITY_COLORS.low
  return (
    <span
      data-testid="severity-badge"
      style={{
        background: palette.background,
        color: palette.color,
        border: `1px solid ${palette.border}`,
        borderRadius: 4,
        padding: '2px 8px',
        fontSize: 12,
        textTransform: 'uppercase',
      }}
    >
      {severity}
    </span>
  )
}

function FilterBar({ severityFilter, typeFilter, onSeverityChange, onTypeChange, count }) {
  return (
    <div style={{ display: 'flex', gap: 12, alignItems: 'center', marginBottom: 16 }}>
      <select
        data-testid="filter-severity"
        value={severityFilter}
        onChange={e => onSeverityChange(e.target.value)}
      >
        <option value="all">all</option>
        {SEVERITIES.map(s => <option key={s} value={s}>{s}</option>)}
      </select>
      <select
        data-testid="filter-type"
        value={typeFilter}
        onChange={e => onTypeChange(e.target.value)}
      >
        <option value="all">all</option>
        {INCIDENT_TYPES.map(t => <option key={t} value={t}>{t}</option>)}
      </select>
      <span data-testid="visible-count">{count} visible</span>
    </div>
  )
}

function IncidentRow({ incident, pending, error, onContain }) {
  return (
    <li
      data-testid="incident-row"
      style={{
        display: 'flex',
        gap: 12,
        alignItems: 'center',
        padding: '8px 0',
        borderBottom: '1px solid #e2e8f0',
      }}
    >
      <SeverityBadge severity={incident.severity} />
      <span>{incident.type}</span>
      <span>{incident.location}</span>
      <span style={{ color: '#64748b' }}>{relativeTime(incident.ts)}</span>
      <button data-testid="contain-btn" disabled={pending} onClick={() => onContain(incident.id)}>
        Contain
      </button>
      {error ? <span data-testid="contain-error" style={{ color: '#b91c1c' }}>Failed — retry</span> : null}
    </li>
  )
}

export function IncidentDashboard() {
  const [incidents, setIncidents] = useState([])
  const [severityFilter, setSeverityFilter] = useState('all')
  const [typeFilter, setTypeFilter] = useState('all')
  const [pendingIds, setPendingIds] = useState([])
  const [failedIds, setFailedIds] = useState([])

  // Part 1: one subscription for the component's lifetime. Filter state is
  // deliberately absent from the dependency list so changing a filter never
  // tears down the feed.
  useEffect(() => {
    return incidentFeed.subscribe(incident => {
      setIncidents(prev =>
        prev.some(i => i.id === incident.id) ? prev : [...prev, incident],
      )
    })
  }, [])

  const active = useMemo(
    () =>
      incidents
        .filter(i => !i.contained)
        .filter(i => severityFilter === 'all' || i.severity === severityFilter)
        .filter(i => typeFilter === 'all' || i.type === typeFilter)
        .sort((a, b) => new Date(b.ts) - new Date(a.ts)),
    [incidents, severityFilter, typeFilter],
  )

  const contained = useMemo(
    () => incidents.filter(i => i.contained),
    [incidents],
  )

  const setContained = useCallback((id, value) => {
    setIncidents(prev => prev.map(i => (i.id === id ? { ...i, contained: value } : i)))
  }, [])

  const onContain = useCallback(
    id => {
      // Optimistic lock applied before awaiting: the row stays in the active
      // list with its button disabled, which is the in-flight state the
      // problem's data-testid contract requires to be observable. The move to
      // the Contained section happens on success.
      setPendingIds(prev => [...prev, id])
      setFailedIds(prev => prev.filter(x => x !== id))

      containIncident(id)
        .then(() => {
          setContained(id, true)
          setPendingIds(prev => prev.filter(x => x !== id))
        })
        .catch(() => {
          // 4. rollback: back to active with an inline error.
          setContained(id, false)
          setPendingIds(prev => prev.filter(x => x !== id))
          setFailedIds(prev => (prev.includes(id) ? prev : [...prev, id]))
        })
    },
    [setContained],
  )

  return (
    <div style={{ fontFamily: 'system-ui', maxWidth: 800, margin: '0 auto', padding: 24 }}>
      <h2 style={{ marginBottom: 16 }}>Incident Dashboard</h2>

      <FilterBar
        severityFilter={severityFilter}
        typeFilter={typeFilter}
        onSeverityChange={setSeverityFilter}
        onTypeChange={setTypeFilter}
        count={active.length}
      />

      {active.length === 0 && contained.length === 0 ? (
        <p style={{ color: '#94a3b8' }}>No incidents yet.</p>
      ) : (
        <ul style={{ listStyle: 'none', padding: 0 }}>
          {active.map(incident => (
            <IncidentRow
              key={incident.id}
              incident={incident}
              pending={pendingIds.includes(incident.id)}
              error={failedIds.includes(incident.id)}
              onContain={onContain}
            />
          ))}
        </ul>
      )}

      {contained.length > 0 ? (
        <section style={{ marginTop: 24 }}>
          <h3>Contained</h3>
          <ul style={{ listStyle: 'none', padding: 0 }}>
            {contained.map(incident => (
              <li key={incident.id} data-testid="contained-row" style={{ padding: '6px 0' }}>
                <SeverityBadge severity={incident.severity} /> {incident.type} — {incident.location}
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </div>
  )
}

export default function App() {
  useEffect(() => {
    incidentFeed.connect()
    return () => incidentFeed.disconnect()
  }, [])

  return <IncidentDashboard />
}
