import { scoreColor, scoreLabel } from '../../types'

interface ScoreChipProps {
  shots: number
  par: number
}

export function ScoreChip({ shots, par }: ScoreChipProps) {
  const delta = shots - par
  const bg = scoreColor(delta)
  const label = scoreLabel(delta)
  const textColor = delta === 0 ? '#1A1C1C' : delta <= -1 ? '#1A1C1C' : '#FFFFFF'

  return (
    <div
      className="flex flex-col items-center justify-center rounded-lg w-12 h-12 text-center border border-outline-variant/20"
      style={{ backgroundColor: bg }}
    >
      <span className="text-label-lg font-semibold" style={{ color: textColor }}>{shots}</span>
      <span className="text-[10px] font-medium leading-none" style={{ color: textColor }}>{label}</span>
    </div>
  )
}
