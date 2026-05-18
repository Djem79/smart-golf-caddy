import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { ScoreChip } from './ScoreChip'

describe('ScoreChip', () => {
  it('renders "Eagle" for delta -2', () => {
    render(<ScoreChip shots={2} par={4} />)
    expect(screen.getByText('Eagle')).toBeInTheDocument()
  })
  it('renders "Birdie" for delta -1', () => {
    render(<ScoreChip shots={3} par={4} />)
    expect(screen.getByText('Birdie')).toBeInTheDocument()
  })
  it('renders "Par" for delta 0', () => {
    render(<ScoreChip shots={4} par={4} />)
    expect(screen.getByText('Par')).toBeInTheDocument()
  })
  it('renders "Bogey" for delta +1', () => {
    render(<ScoreChip shots={5} par={4} />)
    expect(screen.getByText('Bogey')).toBeInTheDocument()
  })
  it('renders the shot count', () => {
    render(<ScoreChip shots={5} par={4} />)
    expect(screen.getByText('5')).toBeInTheDocument()
  })
})
