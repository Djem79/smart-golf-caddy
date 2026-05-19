import { CLUB_ABBREV } from '../../types'

interface ClubChipProps {
  club: string
  selected: boolean
  onSelect: (club: string) => void
  // Optional override label — for custom clubs the parent computes a
  // friendly name via getClubLabel and passes it in. Falls back to the
  // CLUB_ABBREV map for default clubs (or the raw id as a last resort).
  label?: string
}

export function ClubChip({ club, selected, onSelect, label }: ClubChipProps) {
  const displayed = label ?? CLUB_ABBREV[club] ?? club
  return (
    <button
      onClick={() => onSelect(club)}
      className={`px-5 py-2.5 rounded-full text-label-lg font-semibold min-h-touch shrink-0 transition-all border ${
        selected
          ? 'bg-primary text-on-primary border-primary'
          : 'bg-transparent border-outline-variant text-on-surface-variant hover:border-primary'
      }`}
    >
      {displayed}
    </button>
  )
}
