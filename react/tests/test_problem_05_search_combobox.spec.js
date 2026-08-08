import { test as base, expect } from '@playwright/test'

const ALPHA_RESULTS = [
  { id: 'result-alpha', label: 'Alpha', kind: 'Document' },
  { id: 'result-alpine', label: 'Alpine', kind: 'Project' },
]

const test = base.extend({
  freshPage: async ({ page }, use) => {
    await page.route('**/api/recent-selections', route => route.fulfill({ status: 204 }))
    await page.goto('/')
    await use(page)
  },
  seededPage: async ({ page }, use) => {
    await page.route('**/api/search**', route => route.fulfill({ json: ALPHA_RESULTS.map(item => ({ ...item })) }))
    await page.route('**/api/recent-selections', route => route.fulfill({ status: 204 }))
    await page.goto('/')
    await use(page)
  },
})

test.describe('Part 1 — ARIA roles, keyboard navigation, and focus management', () => {
  test('associates a visible label and exposes the combobox relationship', async ({ freshPage: page }) => {
    const input = page.getByRole('combobox', { name: 'Search workspace' })
    await expect(input).toBeVisible()
    await expect(input).toHaveAttribute('aria-autocomplete', 'list')
    await input.focus()
    const listbox = page.getByRole('listbox', { name: 'Search results' })
    await expect(listbox).toBeVisible()
    await expect(input).toHaveAttribute('aria-controls', await listbox.getAttribute('id'))
    await expect(input).toHaveAttribute('aria-expanded', 'true')
  })

  test('manages active descendant and selects with ArrowDown and Enter', async ({ freshPage: page }) => {
    const input = page.getByRole('combobox', { name: 'Search workspace' })
    await input.focus()
    await input.press('ArrowDown')
    const alpha = page.getByRole('option', { name: /Alpha Document/ })
    await expect(alpha).toHaveAttribute('aria-selected', 'true')
    await expect(input).toHaveAttribute('aria-activedescendant', await alpha.getAttribute('id'))
    await input.press('Enter')
    await expect(page.getByTestId('selected-item')).toHaveText('Alpha')
    await expect(input).toBeFocused()
  })

  test('supports wrapping plus Home and End navigation', async ({ freshPage: page }) => {
    const input = page.getByRole('combobox', { name: 'Search workspace' })
    await input.focus()
    await input.press('ArrowUp')
    await expect(page.getByRole('option', { name: /Charlie Person/ })).toHaveAttribute('aria-selected', 'true')
    await input.press('Home')
    await expect(page.getByRole('option', { name: /Alpha Document/ })).toHaveAttribute('aria-selected', 'true')
    await input.press('End')
    await expect(page.getByRole('option', { name: /Charlie Person/ })).toHaveAttribute('aria-selected', 'true')
  })

  test('Escape closes the popup and preserves input focus', async ({ freshPage: page }) => {
    const input = page.getByRole('combobox', { name: 'Search workspace' })
    await input.focus()
    await input.press('ArrowDown')
    await input.press('Escape')
    await expect(input).toHaveAttribute('aria-expanded', 'false')
    await expect(page.getByRole('listbox', { name: 'Search results' })).toBeHidden()
    await expect(input).toBeFocused()
    await expect(input).not.toHaveAttribute('aria-activedescendant', /.+/)
  })

  test('clicking an option uses the same selection result', async ({ freshPage: page }) => {
    const input = page.getByRole('combobox', { name: 'Search workspace' })
    await input.focus()
    await page.getByRole('option', { name: /Bravo Project/ }).click()
    await expect(page.getByTestId('selected-item')).toHaveText('Bravo')
    await expect(input).toHaveAttribute('aria-expanded', 'false')
  })
})

test.describe('Part 2 — debounce, errors, and stale-response suppression', () => {
  test.beforeEach(async ({ page }) => { await page.clock.install() })

  test('waits exactly 300 ms before searching and renders loading/results', async ({ seededPage: page }) => {
    let requests = 0
    let pendingRoute
    await page.unroute('**/api/search**')
    await page.route('**/api/search**', route => {
      requests += 1
      pendingRoute = route
    })
    const input = page.getByRole('combobox', { name: 'Search workspace' })
    await input.fill('alp')
    await page.clock.fastForward(299)
    expect(requests).toBe(0)
    await page.clock.fastForward(1)
    await expect(page.getByTestId('search-status')).toHaveText(/loading/i)
    await pendingRoute.fulfill({ json: ALPHA_RESULTS.map(item => ({ ...item })) })
    await expect(page.getByRole('option')).toHaveCount(2)
    expect(requests).toBe(1)
  })

  test('renders deterministic empty and network error states', async ({ page }) => {
    await page.route('**/api/search**', async route => {
      const query = new URL(route.request().url()).searchParams.get('q')
      if (query === 'error-unique') await route.fulfill({ status: 503 })
      else await route.fulfill({ json: [] })
    })
    await page.goto('/')
    const input = page.getByRole('combobox', { name: 'Search workspace' })
    await input.fill('empty-unique')
    await page.clock.fastForward(300)
    await expect(page.getByTestId('search-status')).toHaveText(/no results/i)
    await input.fill('error-unique')
    await page.clock.fastForward(300)
    await expect(page.getByTestId('search-status')).toHaveText(/search failed/i)
  })

  test('ignores a slower earlier response that arrives last', async ({ page }) => {
    const pending = new Map()
    await page.route('**/api/search**', route => {
      pending.set(new URL(route.request().url()).searchParams.get('q'), route)
    })
    await page.goto('/')
    const input = page.getByRole('combobox', { name: 'Search workspace' })
    await input.fill('al')
    await page.clock.fastForward(300)
    await expect.poll(() => pending.has('al')).toBe(true)
    await input.fill('alp')
    await page.clock.fastForward(300)
    await expect.poll(() => pending.has('alp')).toBe(true)
    await pending.get('alp').fulfill({ json: ALPHA_RESULTS.map(item => ({ ...item })) })
    await expect(page.getByRole('option')).toHaveCount(2)
    await pending.get('al').fulfill({ json: [{ id: 'stale-albatross', label: 'Albatross', kind: 'Document' }] })
    await expect(page.getByRole('option', { name: /Alpha Document/ })).toBeVisible()
    await expect(page.getByRole('option', { name: /Albatross/ })).toHaveCount(0)
  })
})

test.describe('Part 3 — cache and optimistic recent selections', () => {
  test.beforeEach(async ({ page }) => { await page.clock.install() })

  test('serves a repeated successful query from the instance cache', async ({ page }) => {
    let requests = 0
    await page.route('**/api/search**', async route => {
      requests += 1
      await route.fulfill({ json: ALPHA_RESULTS.map(item => ({ ...item })) })
    })
    await page.route('**/api/recent-selections', route => route.fulfill({ status: 204 }))
    await page.goto('/')
    const input = page.getByRole('combobox', { name: 'Search workspace' })
    await input.fill('cache-unique')
    await page.clock.fastForward(300)
    await expect(page.getByRole('option')).toHaveCount(2)
    await input.fill('different-unique')
    await page.clock.fastForward(300)
    await expect.poll(() => requests).toBe(2)
    await input.fill('cache-unique')
    await page.clock.fastForward(300)
    await expect(page.getByRole('option')).toHaveCount(2)
    expect(requests).toBe(2)
  })

  test('shows a recent selection optimistically and keeps it on success', async ({ seededPage: page }) => {
    const input = page.getByRole('combobox', { name: 'Search workspace' })
    await input.fill('optimistic-success-unique')
    await page.clock.fastForward(300)
    await expect(page.getByRole('option')).toHaveCount(2)
    await input.press('ArrowDown')
    await input.press('Enter')
    await expect(page.getByTestId('recent-item')).toHaveText('Alpha')
    await expect(page.getByTestId('recent-error')).toHaveCount(0)
  })

  test('rolls back the optimistic recent item when persistence fails', async ({ page }) => {
    let rejectPersist
    await page.route('**/api/search**', route => route.fulfill({ json: ALPHA_RESULTS.map(item => ({ ...item })) }))
    await page.route('**/api/recent-selections', route => { rejectPersist = route })
    await page.goto('/')
    const input = page.getByRole('combobox', { name: 'Search workspace' })
    await input.fill('rollback-unique')
    await page.clock.fastForward(300)
    await expect(page.getByRole('option')).toHaveCount(2)
    await input.press('ArrowDown')
    await input.press('Enter')
    await expect(page.getByTestId('recent-item')).toHaveText('Alpha')
    await expect.poll(() => Boolean(rejectPersist)).toBe(true)
    await rejectPersist.fulfill({ status: 500 })
    await expect(page.getByTestId('recent-item')).toHaveCount(0)
    await expect(page.getByTestId('recent-error')).toHaveText(/could not save/i)
  })
})
