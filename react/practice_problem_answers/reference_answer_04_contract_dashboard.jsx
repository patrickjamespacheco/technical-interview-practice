/**
 * =============================================================================
 * INTERVIEW PROBLEM 04: Contract Review Dashboard
 * Difficulty: Senior Software Engineer | Estimated time: 45 min
 * =============================================================================
 *
 * CONTEXT
 * -------
 * You're building the contract review dashboard for a contract lifecycle
 * management (CLM) platform. Legal ops teams use this dashboard to monitor
 * contract statuses, find contracts expiring soon, and make quick field edits
 * without leaving the list view.
 *
 * =============================================================================
 * PROVIDED (do not modify)
 * =============================================================================
 *
 * SEED_CONTRACTS    — 6 deterministic contracts used in Playwright tests.
 * STATUS_COLORS     — hex colour map for status badges.
 * updateContractField(contractId, field, value) → Promise
 *                   — mock API call; rejects ~15% of the time.
 *
 * =============================================================================
 * PART 1 — Contract table
 * =============================================================================
 *
 * Render a table (or list) of contracts from SEED_CONTRACTS.
 * Each row must include:
 *   • Contract title
 *   • Status badge (colour-coded using STATUS_COLORS)
 *   • Owner email
 *   • Expiration date
 *
 * Required data-testid attributes:
 *   • data-testid="contract-row"    on every contract row
 *   • data-testid="status-badge"    on the status badge inside each row
 *
 * =============================================================================
 * PART 2 — Filter, search, and sort
 * =============================================================================
 *
 * Add three controls above the table:
 *
 * 1. Status filter — a <select> that filters by contract status.
 *    Options: "All", "draft", "in_review", "approved", "active", "expired"
 *    data-testid="filter-status"
 *
 * 2. Text search — an <input> that filters rows by title (case-insensitive
 *    substring match).
 *    data-testid="search-input"
 *
 * 3. Sort by expiration — a <button> that toggles between ascending and
 *    descending expiration date order.
 *    data-testid="sort-expiration"
 *
 * Use useMemo to derive the filtered + sorted list from the raw contracts state.
 * Show a row count: "Showing N contracts".
 *
 * =============================================================================
 * PART 3 — Inline field editing with optimistic updates
 * =============================================================================
 *
 * Make the contract title and owner email cells inline-editable:
 *
 * • Double-clicking a title or email cell enters edit mode (renders an <input>).
 * • Pressing Enter or clicking a "Save" button calls updateContractField and
 *   shows a spinner (data-testid="save-spinner") while the request is in-flight.
 * • On success: update the cell with the new value.
 * • On failure: revert to the previous value and show an inline error message.
 * • While saving, the input should be disabled.
 *
 * Required data-testid attributes:
 *   • data-testid="editable-field"   on every editable cell (view mode)
 *   • data-testid="save-spinner"     on the loading indicator during save
 *
 * =============================================================================
 */

// ── Seed data (do not modify) ─────────────────────────────────────────────────

export const SEED_CONTRACTS = [
  {
    contract_id: 'con-001',
    title: 'Vendor MSA',
    owner_email: 'legal@acme.com',
    status: 'active',
    expires_on: '2025-09-30',
  },
  {
    contract_id: 'con-002',
    title: 'SaaS Subscription Agreement',
    owner_email: 'ops@acme.com',
    status: 'in_review',
    expires_on: '2025-12-31',
  },
  {
    contract_id: 'con-003',
    title: 'NDA — Design Partner',
    owner_email: 'bizdev@acme.com',
    status: 'approved',
    expires_on: '2026-03-15',
  },
  {
    contract_id: 'con-004',
    title: 'Office Lease',
    owner_email: 'finance@acme.com',
    status: 'active',
    expires_on: '2027-06-01',
  },
  {
    contract_id: 'con-005',
    title: 'Legacy Reseller Agreement',
    owner_email: 'sales@acme.com',
    status: 'expired',
    expires_on: '2024-01-01',
  },
  {
    contract_id: 'con-006',
    title: 'Marketing Agency SOW',
    owner_email: 'marketing@acme.com',
    status: 'draft',
    expires_on: '2025-11-30',
  },
]

export const STATUS_COLORS = {
  draft:     '#94a3b8',
  in_review: '#f59e0b',
  approved:  '#3b82f6',
  active:    '#22c55e',
  expired:   '#ef4444',
}

/**
 * Mock API call. Resolves after ~300 ms; rejects ~15% of the time.
 *
 * @param {string} contractId
 * @param {string} field        - "title" | "owner_email"
 * @param {string} value        - new value
 * @returns {Promise<{ contract_id: string, field: string, value: string }>}
 */
export function updateContractField(contractId, field, value) {
  return new Promise((resolve, reject) => {
    setTimeout(() => {
      if (Math.random() < 0.15) {
        reject(new Error('Save failed — please try again.'))
      } else {
        resolve({ contract_id: contractId, field, value })
      }
    }, 300)
  })
}

// ── Your implementation goes below ───────────────────────────────────────────

import React, { useState, useMemo, useCallback } from 'react'

const STATUS_OPTIONS = ['draft', 'in_review', 'approved', 'active', 'expired']

function StatusBadge({ status }) {
  return (
    <span
      data-testid="status-badge"
      style={{
        background: STATUS_COLORS[status],
        color: '#fff',
        borderRadius: 4,
        padding: '2px 8px',
        fontSize: 12,
      }}
    >
      {status}
    </span>
  )
}

function EditableCell({ contractId, field, value, onSave }) {
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(value)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)

  function commit() {
    setSaving(true)
    setError(null)
    onSave(contractId, field, draft)
      .then(() => {
        setSaving(false)
        setEditing(false)
      })
      .catch(err => {
        // Revert to the last known-good value and surface the failure.
        setDraft(value)
        setSaving(false)
        setEditing(false)
        setError(err.message)
      })
  }

  if (!editing) {
    return (
      <span>
        <span data-testid="editable-field" onDoubleClick={() => { setDraft(value); setEditing(true) }}>
          {value}
        </span>
        {error ? <span data-testid="save-error" style={{ color: '#ef4444' }}> {error}</span> : null}
      </span>
    )
  }

  return (
    <span>
      <input
        data-testid="edit-input"
        value={draft}
        disabled={saving}
        onChange={e => setDraft(e.target.value)}
        onKeyDown={e => { if (e.key === 'Enter') commit() }}
      />
      <button data-testid="save-btn" disabled={saving} onClick={commit}>Save</button>
      {saving ? <span data-testid="save-spinner">Saving…</span> : null}
    </span>
  )
}

export default function App() {
  const [contracts, setContracts] = useState(() => SEED_CONTRACTS.map(c => ({ ...c })))
  const [status, setStatus] = useState('all')
  const [query, setQuery] = useState('')
  const [ascending, setAscending] = useState(true)

  const visible = useMemo(() => {
    const needle = query.trim().toLowerCase()
    return contracts
      .filter(c => status === 'all' || c.status === status)
      .filter(c => needle === '' || c.title.toLowerCase().includes(needle))
      .slice()
      .sort((a, b) =>
        ascending
          ? a.expires_on.localeCompare(b.expires_on)
          : b.expires_on.localeCompare(a.expires_on),
      )
  }, [contracts, status, query, ascending])

  const onSave = useCallback(
    (contractId, field, value) =>
      updateContractField(contractId, field, value).then(result => {
        setContracts(prev =>
          prev.map(c => (c.contract_id === contractId ? { ...c, [field]: result.value } : c)),
        )
        return result
      }),
    [],
  )

  return (
    <div style={{ fontFamily: 'system-ui', maxWidth: 900, margin: '0 auto', padding: 24 }}>
      <h2 style={{ marginBottom: 16 }}>Contract Review Dashboard</h2>

      <div style={{ display: 'flex', gap: 12, marginBottom: 16 }}>
        <select data-testid="filter-status" value={status} onChange={e => setStatus(e.target.value)}>
          <option value="all">All</option>
          {STATUS_OPTIONS.map(s => <option key={s} value={s}>{s}</option>)}
        </select>
        <input
          data-testid="search-input"
          placeholder="Search titles"
          value={query}
          onChange={e => setQuery(e.target.value)}
        />
        <button data-testid="sort-expiration" onClick={() => setAscending(a => !a)}>
          Expiration {ascending ? '↑' : '↓'}
        </button>
      </div>

      <p data-testid="row-count">Showing {visible.length} contracts</p>

      <ul style={{ listStyle: 'none', padding: 0 }}>
        {visible.map(contract => (
          <li
            key={contract.contract_id}
            data-testid="contract-row"
            style={{
              display: 'flex',
              gap: 12,
              alignItems: 'center',
              padding: '8px 0',
              borderBottom: '1px solid #e2e8f0',
            }}
          >
            <EditableCell
              contractId={contract.contract_id}
              field="title"
              value={contract.title}
              onSave={onSave}
            />
            <StatusBadge status={contract.status} />
            <EditableCell
              contractId={contract.contract_id}
              field="owner_email"
              value={contract.owner_email}
              onSave={onSave}
            />
            <span>{contract.expires_on}</span>
          </li>
        ))}
      </ul>
    </div>
  )
}
