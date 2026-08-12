/**
 * =============================================================================
 * INTERVIEW PROBLEM 3: Alert Triage Console
 * Difficulty: Senior Software Engineer | Estimated time: 45–60 min
 * =============================================================================
 *
 * CONTEXT
 * -------
 * You're building the dispatch operations console for an emergency-response
 * platform. Incoming alerts from radio dispatch and field sensors stream in
 * continuously. Operators triage them by assigning to available field units
 * or acknowledging alerts that don't require dispatch.
 *
 * A working mock alert stream, available units, and API stubs are provided.
 * Do NOT modify anything in the "PROVIDED — DO NOT MODIFY" sections.
 *
 * =============================================================================
 *
 * PART 1 — Alert queue  (~15 min)
 * ────────────────────────────────
 * Render an <AlertTriageConsole /> component that:
 *   - Subscribes to `alertStream` on mount and unsubscribes on unmount.
 *   - Displays unacknowledged, unassigned alerts sorted by severity descending
 *     (5 = highest), then by timestamp ascending (oldest first within same sev).
 *   - Each row shows: severity badge (1–5, color-coded), alert type, message,
 *     source, and relative time ("3 min ago").
 *
 * Data-testid requirements (Playwright relies on these):
 *   data-testid="alert-row"      — wrapper element for each alert row
 *   data-testid="severity-badge" — the severity indicator inside each row
 *
 * PART 2 — Assign to unit  (~15 min)
 * ────────────────────────────────────
 * Add an assign action to each unassigned, unacknowledged alert row:
 *   - A <select data-testid="unit-select"> populated with UNITS.
 *   - A <button data-testid="assign-btn"> that calls assignAlert(alertId, unitId).
 *
 * When the assignment succeeds:
 *   - Show the assigned unit name on the row (no separate section needed yet).
 *   - Mark the alert as assigned in local state.
 * On failure (~15% of the time):
 *   - Revert to unassigned; show an inline error ("Assignment failed — retry").
 * While in-flight:
 *   - Disable the assign button and the unit select.
 *
 * PART 3 — Tab navigation and bulk-ack  (~15 min)
 * ─────────────────────────────────────────────────
 * Add a tab bar at the top of the console with three tabs:
 *   Queued | Assigned | Acknowledged
 *
 * Data-testid requirements:
 *   data-testid="tab-queued"        — Queued tab button
 *   data-testid="tab-assigned"      — Assigned tab button
 *   data-testid="tab-acknowledged"  — Acknowledged tab button
 *
 * Each tab shows its count in parentheses, e.g. "Queued (3)".
 *
 * Switching tabs changes which alerts are shown:
 *   Queued       — unassigned AND not acknowledged
 *   Assigned     — assigned AND not acknowledged
 *   Acknowledged — acknowledged (by any means)
 *
 * On the Queued tab, add an "Ack All" button (data-testid="ack-all-btn") that
 * calls acknowledgeAlert(id) for every currently visible queued alert and marks
 * them all as acknowledged. Fire all calls in parallel (Promise.all or similar).
 *
 * =============================================================================
 */

import React, { useState, useEffect, useMemo, useCallback } from 'react'

// =============================================================================
// PROVIDED — DO NOT MODIFY
// =============================================================================

export const ALERT_TYPES = ['radio-dispatch', 'sensor-alert', 'social-monitor', 'field-report']

export const SEVERITY_COLORS = {
  5: { background: '#fef2f2', color: '#991b1b', border: '#fca5a5', label: 'P1' },
  4: { background: '#fff7ed', color: '#9a3412', border: '#fdba74', label: 'P2' },
  3: { background: '#fefce8', color: '#854d0e', border: '#fde047', label: 'P3' },
  2: { background: '#eff6ff', color: '#1e40af', border: '#93c5fd', label: 'P4' },
  1: { background: '#f0fdf4', color: '#166534', border: '#86efac', label: 'P5' },
}

/**
 * Available field units that alerts can be dispatched to.
 */
export const UNITS = [
  { id: 'unit-12', name: 'Alpha Team',  type: 'patrol' },
  { id: 'unit-14', name: 'Beta Team',   type: 'patrol' },
  { id: 'unit-21', name: 'Fire Unit 3', type: 'fire'   },
  { id: 'unit-33', name: 'Medic 5',     type: 'ems'    },
  { id: 'unit-45', name: 'SWAT Alpha',  type: 'swat'   },
]

/**
 * Deterministic seed alerts — appear immediately on connect.
 * Playwright tests rely on the message text and severity values here.
 */
export const SEED_ALERTS = [
  {
    id:           'alt-s1',
    type:         'radio-dispatch',
    severity:     5,
    message:      'Reports of shots fired at Central Station',
    source:       'radio-north',
    ts:           new Date(Date.now() - 1  * 60_000).toISOString(),
    assignedTo:   null,
    acknowledged: false,
  },
  {
    id:           'alt-s2',
    type:         'sensor-alert',
    severity:     4,
    message:      'Collision detected on Highway 12',
    source:       'sensor-grid-east',
    ts:           new Date(Date.now() - 3  * 60_000).toISOString(),
    assignedTo:   null,
    acknowledged: false,
  },
  {
    id:           'alt-s3',
    type:         'radio-dispatch',
    severity:     3,
    message:      'Structural fire reported at Warehouse District',
    source:       'radio-south',
    ts:           new Date(Date.now() - 6  * 60_000).toISOString(),
    assignedTo:   null,
    acknowledged: false,
  },
  {
    id:           'alt-s4',
    type:         'sensor-alert',
    severity:     2,
    message:      'Flooding sensors triggered at Riverside Park',
    source:       'sensor-grid-west',
    ts:           new Date(Date.now() - 10 * 60_000).toISOString(),
    assignedTo:   null,
    acknowledged: false,
  },
]

let _alertId = 100

const MESSAGES = {
  'radio-dispatch': [
    'Officer requesting backup at intersection of 5th and Main',
    'Suspicious vehicle reported near school zone',
    'Domestic disturbance call in progress',
  ],
  'sensor-alert': [
    'Gunshot detection triggered — confidence 87%',
    'Traffic sensor anomaly on Bridge Road',
    'Environmental sensor spike at industrial zone',
  ],
  'social-monitor': [
    'Spike in 911-related social posts — downtown area',
    'Crowd incident reported via social media',
  ],
  'field-report': [
    'Officer on scene — requesting additional units',
    'Situation escalating — requesting supervisor',
  ],
}

function makeRandomAlert() {
  const type     = ALERT_TYPES[Math.floor(Math.random() * ALERT_TYPES.length)]
  const msgs     = MESSAGES[type]
  const severity = Math.ceil(Math.random() * 5)
  return {
    id:           `alt-${_alertId++}`,
    type,
    severity,
    message:      msgs[Math.floor(Math.random() * msgs.length)],
    source:       `source-${Math.floor(Math.random() * 10)}`,
    ts:           new Date().toISOString(),
    assignedTo:   null,
    acknowledged: false,
  }
}

/**
 * createAlertStream() → { connect, disconnect, subscribe }
 *
 * connect()           — seed alerts arrive within 300ms, then new random
 *                       alerts every 2.5s
 * disconnect()        — stop emitting
 * subscribe(handler)  — returns unsubscribe fn
 */
export function createAlertStream() {
  let handlers = []
  let timerId  = null

  function emit(alert) {
    handlers.forEach(h => h({ ...alert }))
  }

  return {
    connect() {
      SEED_ALERTS.forEach((alert, i) => setTimeout(() => emit(alert), i * 50))
      timerId = setInterval(() => emit(makeRandomAlert()), 2500)
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
 * assignAlert(alertId, unitId) → Promise<void>
 * Simulates a POST /alerts/:id/assign API call.
 * Resolves after ~400ms. Rejects ~15% of the time.
 */
export function assignAlert(alertId, unitId) {
  return new Promise((resolve, reject) => {
    setTimeout(() => {
      Math.random() < 0.15
        ? reject(new Error(`Failed to assign ${alertId} to ${unitId}`))
        : resolve()
    }, 400)
  })
}

/**
 * acknowledgeAlert(alertId) → Promise<void>
 * Always resolves after ~300ms.
 */
export function acknowledgeAlert(alertId) {
  return new Promise(resolve => setTimeout(resolve, 300))
}

// Shared singleton — import this in your component
export const alertStream = createAlertStream()

// =============================================================================
// YOUR WORK STARTS HERE
// =============================================================================

// ---------------------------------------------------------------------------
// PART 1 — Implement AlertTriageConsole
// ---------------------------------------------------------------------------

function relativeTime(ts) {
  const mins = Math.max(0, Math.round((Date.now() - new Date(ts).getTime()) / 60_000))
  return mins < 1 ? 'just now' : `${mins} min ago`
}

function SeverityBadge({ severity }) {
  const palette = SEVERITY_COLORS[severity] ?? SEVERITY_COLORS[1]
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
      }}
    >
      {severity} {palette.label}
    </span>
  )
}

function TabBar({ activeTab, counts, onTabChange }) {
  const tabs = [
    ['queued', 'Queued'],
    ['assigned', 'Assigned'],
    ['acknowledged', 'Acknowledged'],
  ]
  return (
    <div style={{ display: 'flex', gap: 8, marginBottom: 16 }}>
      {tabs.map(([key, label]) => (
        <button
          key={key}
          data-testid={`tab-${key}`}
          onClick={() => onTabChange(key)}
          style={{ fontWeight: activeTab === key ? 700 : 400 }}
        >
          {label} ({counts[key]})
        </button>
      ))}
    </div>
  )
}

function AlertRow({ alert, units, pending, error, onAssign }) {
  const [unitId, setUnitId] = React.useState(units[0].id)
  const assignable = !alert.acknowledged && !alert.assignedTo
  const assignedUnit = units.find(u => u.id === alert.assignedTo)

  return (
    <li
      data-testid="alert-row"
      style={{
        display: 'flex',
        gap: 12,
        alignItems: 'center',
        padding: '8px 0',
        borderBottom: '1px solid #e2e8f0',
      }}
    >
      <SeverityBadge severity={alert.severity} />
      <span>{alert.type}</span>
      <span style={{ flex: 1 }}>{alert.message}</span>
      <span>{alert.source}</span>
      <span style={{ color: '#64748b' }}>{relativeTime(alert.ts)}</span>

      {assignable ? (
        <>
          <select
            data-testid="unit-select"
            value={unitId}
            disabled={pending}
            onChange={e => setUnitId(e.target.value)}
          >
            {units.map(u => <option key={u.id} value={u.id}>{u.name}</option>)}
          </select>
          <button data-testid="assign-btn" disabled={pending} onClick={() => onAssign(alert.id, unitId)}>
            Assign
          </button>
        </>
      ) : null}

      {assignedUnit ? <span data-testid="assigned-unit">{assignedUnit.name}</span> : null}
      {error ? (
        <span data-testid="assign-error" style={{ color: '#b91c1c' }}>Assignment failed — retry</span>
      ) : null}
    </li>
  )
}

export function AlertTriageConsole() {
  const [alerts, setAlerts] = useState([])
  const [activeTab, setActiveTab] = useState('queued')
  const [pendingIds, setPendingIds] = useState([])
  const [failedIds, setFailedIds] = useState([])

  // Part 1: subscribe once; tab and assignment state never tear it down.
  useEffect(() => {
    return alertStream.subscribe(alert => {
      setAlerts(prev => (prev.some(a => a.id === alert.id) ? prev : [...prev, alert]))
    })
  }, [])

  const buckets = useMemo(() => {
    const bySeverityThenAge = (a, b) =>
      b.severity - a.severity || new Date(a.ts) - new Date(b.ts)
    return {
      queued: alerts.filter(a => !a.acknowledged && !a.assignedTo).sort(bySeverityThenAge),
      assigned: alerts.filter(a => !a.acknowledged && a.assignedTo).sort(bySeverityThenAge),
      acknowledged: alerts.filter(a => a.acknowledged).sort(bySeverityThenAge),
    }
  }, [alerts])

  const counts = {
    queued: buckets.queued.length,
    assigned: buckets.assigned.length,
    acknowledged: buckets.acknowledged.length,
  }

  const onAssign = useCallback((alertId, unitId) => {
    setPendingIds(prev => [...prev, alertId])
    setFailedIds(prev => prev.filter(x => x !== alertId))

    assignAlert(alertId, unitId)
      .then(() => {
        setAlerts(prev => prev.map(a => (a.id === alertId ? { ...a, assignedTo: unitId } : a)))
        setPendingIds(prev => prev.filter(x => x !== alertId))
      })
      .catch(() => {
        setAlerts(prev => prev.map(a => (a.id === alertId ? { ...a, assignedTo: null } : a)))
        setPendingIds(prev => prev.filter(x => x !== alertId))
        setFailedIds(prev => (prev.includes(alertId) ? prev : [...prev, alertId]))
      })
  }, [])

  const onAckAll = useCallback(() => {
    const ids = buckets.queued.map(a => a.id)
    Promise.all(ids.map(id => acknowledgeAlert(id))).then(() => {
      setAlerts(prev => prev.map(a => (ids.includes(a.id) ? { ...a, acknowledged: true } : a)))
    })
  }, [buckets.queued])

  const visible = buckets[activeTab]

  return (
    <div style={{ fontFamily: 'system-ui', maxWidth: 900, margin: '0 auto', padding: 24 }}>
      <h2 style={{ marginBottom: 16 }}>Alert Triage Console</h2>

      <TabBar activeTab={activeTab} counts={counts} onTabChange={setActiveTab} />

      {activeTab === 'queued' ? (
        <button data-testid="ack-all-btn" onClick={onAckAll} style={{ marginBottom: 12 }}>
          Ack All
        </button>
      ) : null}

      {visible.length === 0 ? (
        <p style={{ color: '#94a3b8' }}>No alerts yet.</p>
      ) : (
        <ul style={{ listStyle: 'none', padding: 0 }}>
          {visible.map(alert => (
            <AlertRow
              key={alert.id}
              alert={alert}
              units={UNITS}
              pending={pendingIds.includes(alert.id)}
              error={failedIds.includes(alert.id)}
              onAssign={onAssign}
            />
          ))}
        </ul>
      )}
    </div>
  )
}

export default function App() {
  useEffect(() => {
    alertStream.connect()
    return () => alertStream.disconnect()
  }, [])

  return <AlertTriageConsole />
}
