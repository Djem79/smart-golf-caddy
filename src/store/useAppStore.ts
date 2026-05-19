import { create } from 'zustand'

interface AppStore {
  // Default club to pre-select on the next hole. Carries the user's preference
  // across hole navigation without touching Firestore. Reset to 'Driver' when
  // no club has been chosen yet.
  lastClubUsed: string
  setLastClubUsed: (club: string) => void
}

export const useAppStore = create<AppStore>((set) => ({
  lastClubUsed: 'Driver',
  setLastClubUsed: (club) => set({ lastClubUsed: club }),
}))
