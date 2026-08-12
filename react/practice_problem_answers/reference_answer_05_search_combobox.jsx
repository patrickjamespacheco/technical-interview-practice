/**
 * =============================================================================
 * INTERVIEW PROBLEM 05: Accessible Async Search Combobox
 * Difficulty: Senior Software Engineer | Estimated time: 45 minutes
 * =============================================================================
 *
 * CONTEXT
 * -------
 * Build a command-style search control for a productivity SaaS. Accessibility
 * is a functional requirement: screen-reader and keyboard users must receive
 * the same state and selection behavior as pointer users.
 *
 * PROVIDED — DO NOT MODIFY
 * ------------------------
 * INITIAL_ITEMS, searchItems(query), and persistSelection(item) are supplied.
 * Tests intercept their HTTP requests, so do not replace these service seams.
 * Make defensive copies before storing provided arrays in mutable state.
 *
 * PART 1 — Accessible local combobox
 * -----------------------------------
 * Implement `useComboboxState(items, onSelect)` and use it in
 * `AccessibleSearchCombobox` to search/select from INITIAL_ITEMS.
 *
 * Requirements:
 *   - A visible <label> named "Search workspace" is associated to the input.
 *   - The input has role="combobox", aria-autocomplete="list",
 *     aria-controls, aria-expanded, and aria-activedescendant while active.
 *   - Results use role="listbox" and role="option"; the active option has
 *     aria-selected="true" and a stable, readable DOM id derived from item.id.
 *   - ArrowDown/ArrowUp move and wrap; Home/End jump; Enter selects; Escape
 *     closes the popup without moving focus away from the input.
 *   - Clicking an option uses the same selection path as Enter.
 *
 * PART 2 — Debounced asynchronous item source
 * --------------------------------------------
 * Implement `useAsyncSearch(query, search, debounceMs = 300)`. Non-empty
 * queries call `search(query)` only after 300 ms. Expose loading, success,
 * empty, and error states. Suppress stale responses: only the newest request
 * may update visible results. Feed its items into the Part 1 hook and render
 * options through the same listbox/selection path—do not build a second list.
 *
 * PART 3 — Cache and optimistic recent selections
 * ------------------------------------------------
 * Implement `useSearchData(search, persist)`. It owns an instance-local query
 * cache and exposes a cached search function. It also exposes the selection
 * handler passed to Part 1: add a selection to the recent list immediately,
 * call persist, and remove that optimistic entry plus show an error on failure.
 * Cache arrays defensively. Repeating a successful query must not call search.
 *
 * COMPOSITION CHAIN
 * -----------------
 * `useComboboxState` drives selection -> `useAsyncSearch` replaces its items ->
 * `useSearchData` wraps fetch/persist and feeds the same selection handler.
 *
 * Required data-testid contract (supplements, never replaces, semantic ARIA):
 *   search-input, search-listbox, search-option, search-status, selected-item,
 *   recent-list, recent-item, recent-error
 *
 * Example:
 *   Type "alp" and advance fake time 300 ms: Alpha and Alpine appear.
 *   Press ArrowDown, then Enter: Alpha is selected immediately.
 *   If a slower earlier request for "al" resolves afterward, it is ignored.
 * =============================================================================
 */

import React from 'react'

export const INITIAL_ITEMS = [
  { id: 'doc-alpha', label: 'Alpha', kind: 'Document' },
  { id: 'doc-alpine', label: 'Alpine', kind: 'Document' },
  { id: 'project-bravo', label: 'Bravo', kind: 'Project' },
  { id: 'person-charlie', label: 'Charlie', kind: 'Person' },
]

export async function searchItems(query) {
  const response = await fetch(`/api/search?q=${encodeURIComponent(query)}`)
  if (!response.ok) throw new Error('Search failed')
  return response.json()
}

export async function persistSelection(item) {
  const response = await fetch('/api/recent-selections', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ itemId: item.id }),
  })
  if (!response.ok) throw new Error('Could not save recent selection')
}

const LISTBOX_ID = 'search-listbox'
const optionDomId = item => `search-option-${item.id}`

// PART 1
export function useComboboxState(items, onSelect) {
  const [open, setOpen] = React.useState(false)
  const [activeIndex, setActiveIndex] = React.useState(-1)

  // A shrinking result set must not leave the active index dangling past the end.
  React.useEffect(() => {
    setActiveIndex(current => (current >= items.length ? -1 : current))
  }, [items])

  const activeItem = activeIndex >= 0 ? items[activeIndex] : undefined

  const move = React.useCallback(
    delta => {
      setOpen(true)
      setActiveIndex(current => {
        if (items.length === 0) return -1
        // Wrap in both directions; an inactive list enters from the near end.
        if (current < 0) return delta > 0 ? 0 : items.length - 1
        return (current + delta + items.length) % items.length
      })
    },
    [items.length],
  )

  const select = React.useCallback(
    item => {
      if (!item) return
      setOpen(false)
      setActiveIndex(-1)
      onSelect(item)
    },
    [onSelect],
  )

  const onKeyDown = React.useCallback(
    event => {
      switch (event.key) {
        case 'ArrowDown':
          event.preventDefault()
          move(1)
          break
        case 'ArrowUp':
          event.preventDefault()
          move(-1)
          break
        case 'Home':
          event.preventDefault()
          setOpen(true)
          setActiveIndex(items.length > 0 ? 0 : -1)
          break
        case 'End':
          event.preventDefault()
          setOpen(true)
          setActiveIndex(items.length > 0 ? items.length - 1 : -1)
          break
        case 'Enter':
          event.preventDefault()
          select(activeItem)
          break
        case 'Escape':
          event.preventDefault()
          // Close without moving focus: the input keeps it.
          setOpen(false)
          setActiveIndex(-1)
          break
        default:
          break
      }
    },
    [move, select, activeItem, items.length],
  )

  return {
    open,
    activeIndex,
    activeItem,
    // Clicking an option runs the same path as Enter.
    selectItem: select,
    onKeyDown,
    onFocus: React.useCallback(() => setOpen(true), []),
    openList: React.useCallback(() => setOpen(true), []),
  }
}

// PART 2
export function useAsyncSearch(query, search, debounceMs = 300) {
  const [state, setState] = React.useState({ status: 'idle', items: [] })
  // Monotonic request id: only the newest response may touch visible state.
  const latestRequest = React.useRef(0)

  React.useEffect(() => {
    const trimmed = query.trim()
    if (trimmed === '') {
      latestRequest.current += 1
      setState({ status: 'idle', items: [] })
      return undefined
    }

    const timerId = setTimeout(() => {
      const requestId = latestRequest.current + 1
      latestRequest.current = requestId
      setState({ status: 'loading', items: [] })

      Promise.resolve()
        .then(() => search(trimmed))
        .then(items => {
          if (latestRequest.current !== requestId) return
          setState({ status: items.length === 0 ? 'empty' : 'success', items })
        })
        .catch(() => {
          if (latestRequest.current !== requestId) return
          setState({ status: 'error', items: [] })
        })
    }, debounceMs)

    return () => clearTimeout(timerId)
  }, [query, search, debounceMs])

  return state
}

// PART 3
export function useSearchData(search, persist) {
  const [recents, setRecents] = React.useState([])
  const [error, setError] = React.useState(null)
  // Instance-local cache: a repeated successful query never calls search again.
  const cache = React.useRef(new Map())

  const cachedSearch = React.useCallback(
    async query => {
      const cached = cache.current.get(query)
      if (cached) return cached.map(item => ({ ...item }))

      const items = await search(query)
      const stored = items.map(item => ({ ...item }))
      cache.current.set(query, stored)
      return stored.map(item => ({ ...item }))
    },
    [search],
  )

  const onSelect = React.useCallback(
    item => {
      // Optimistic: the recent entry is visible before persistence resolves.
      setRecents(prev => [item, ...prev.filter(r => r.id !== item.id)])
      setError(null)

      Promise.resolve()
        .then(() => persist(item))
        .catch(err => {
          setRecents(prev => prev.filter(r => r.id !== item.id))
          setError(err.message || 'Could not save recent selection')
        })
    },
    [persist],
  )

  return { cachedSearch, recents, error, onSelect }
}

const STATUS_TEXT = {
  loading: 'Loading results',
  empty: 'No results',
  error: 'Search failed',
}

export function AccessibleSearchCombobox({
  search = searchItems,
  persist = persistSelection,
}) {
  const [query, setQuery] = React.useState('')
  const [selected, setSelected] = React.useState(null)

  const { cachedSearch, recents, error: recentError, onSelect: rememberSelection } =
    useSearchData(search, persist)

  const async_ = useAsyncSearch(query, cachedSearch)

  // One list feeds the combobox: local items until there is a query, then
  // whatever the async source most recently returned.
  const items = query.trim() === '' ? INITIAL_ITEMS : async_.items

  const handleSelect = React.useCallback(
    item => {
      setSelected(item)
      rememberSelection(item)
    },
    [rememberSelection],
  )

  const combobox = useComboboxState(items, handleSelect)
  const { open, activeItem, selectItem, onKeyDown, onFocus } = combobox

  const activeDescendant = open && activeItem ? optionDomId(activeItem) : undefined

  return (
    <div style={{ fontFamily: 'system-ui', maxWidth: 520, margin: '0 auto', padding: 24 }}>
      <label htmlFor="search-input">Search workspace</label>
      <input
        id="search-input"
        data-testid="search-input"
        role="combobox"
        aria-autocomplete="list"
        aria-controls={LISTBOX_ID}
        aria-expanded={open ? 'true' : 'false'}
        {...(activeDescendant ? { 'aria-activedescendant': activeDescendant } : {})}
        value={query}
        onChange={event => { setQuery(event.target.value); combobox.openList() }}
        onFocus={onFocus}
        onKeyDown={onKeyDown}
        style={{ display: 'block', width: '100%', padding: 8, marginTop: 4 }}
      />

      <p data-testid="search-status" role="status" aria-live="polite">
        {STATUS_TEXT[async_.status] ?? ''}
      </p>

      {open ? (
        <ul
          id={LISTBOX_ID}
          data-testid="search-listbox"
          role="listbox"
          aria-label="Search results"
          style={{ listStyle: 'none', margin: 0, padding: 0, border: '1px solid #cbd5e1' }}
        >
          {items.map(item => {
            const isActive = activeItem?.id === item.id
            return (
              <li
                key={item.id}
                id={optionDomId(item)}
                data-testid="search-option"
                role="option"
                aria-selected={isActive ? 'true' : 'false'}
                onMouseDown={event => event.preventDefault()}
                onClick={() => selectItem(item)}
                style={{ padding: '6px 8px', background: isActive ? '#e0e7ff' : 'transparent' }}
              >
                {item.label} {item.kind}
              </li>
            )
          })}
        </ul>
      ) : null}

      {selected ? <p data-testid="selected-item">{selected.label}</p> : null}

      <ul data-testid="recent-list" style={{ listStyle: 'none', padding: 0 }}>
        {recents.map(item => (
          <li key={item.id} data-testid="recent-item">{item.label}</li>
        ))}
      </ul>

      {recentError ? <p data-testid="recent-error">{recentError}</p> : null}
    </div>
  )
}

export default function App() {
  return <AccessibleSearchCombobox />
}
