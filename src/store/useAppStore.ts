import { create } from 'zustand'
import type { Round } from '../types'

interface AppStore {
  activeRound: Round | null
  currentHoleIndex: number
  lastClubUsed: string

  setActiveRound: (round: Round | null) => void
  setCurrentHoleIndex: (index: number) => void
  setLastClubUsed: (club: string) => void
}

export const useAppStore = create<AppStore>((set) => ({
  activeRound: null,
  currentHoleIndex: 0,
  lastClubUsed: 'Driver',

  setActiveRound: (round) => set({ activeRound: round }),
  setCurrentHoleIndex: (index) => set({ currentHoleIndex: index }),
  setLastClubUsed: (club) => set({ lastClubUsed: club }),
}))
