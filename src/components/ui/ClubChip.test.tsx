import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { ClubChip } from './ClubChip'

describe('ClubChip', () => {
  it('renders abbreviated club name', () => {
    render(<ClubChip club="Driver" selected={false} onSelect={vi.fn()} />)
    expect(screen.getByText('DRV')).toBeInTheDocument()
  })
  it('calls onSelect with club name on click', () => {
    const onSelect = vi.fn()
    render(<ClubChip club="Putter" selected={false} onSelect={onSelect} />)
    fireEvent.click(screen.getByRole('button'))
    expect(onSelect).toHaveBeenCalledWith('Putter')
  })
  it('applies selected styling when selected=true', () => {
    render(<ClubChip club="7i" selected={true} onSelect={vi.fn()} />)
    const btn = screen.getByRole('button')
    expect(btn.className).toContain('bg-primary')
  })
})
