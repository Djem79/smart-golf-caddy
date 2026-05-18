import { CLUB_ABBREV } from '../../types'

interface ClubChipProps {
  club: string
  selected: boolean
  onSelect: (club: string) => void
}

export function ClubChip({ club, selected, onSelect }: ClubChipProps) {
  return (
    <button
      onClick={() => onSelect(club)}
      className={`px-3 py-2 rounded-full text-label-lg font-semibold min-h-touch min-w-touch shrink-0 transition-colors ${
        selected
          ? 'bg-primary text-on-primary'
          : 'bg-surface-container border border-outline-variant text-on-surface-variant'
      }`}
    >
      {CLUB_ABBREV[club] ?? club}
    </button>
  )
}
