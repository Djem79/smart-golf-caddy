import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { QRCodeSVG } from 'qrcode.react'
import { Play, Check, Copy } from 'lucide-react'
import { useAuth } from '../hooks/useAuth'
import { subscribeToRound, startRound, leaveLobby } from '../services/rounds'
import type { Round } from '../types'
import { Button } from '../components/ui/Button'
import { Card } from '../components/ui/Card'
import { Avatar } from '../components/ui/Avatar'
import { ConfirmDialog } from '../components/ui/ConfirmDialog'
import { PageHeader } from '../components/layout/PageHeader'
import { pluralRu } from '../utils/intl'

export function GroupLobby() {
  const { roundId } = useParams<{ roundId: string }>()
  const navigate = useNavigate()
  const { user } = useAuth()
  const [round, setRound] = useState<Round | null>(null)
  const [starting, setStarting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)
  const [showLeaveConfirm, setShowLeaveConfirm] = useState(false)

  useEffect(() => {
    if (!roundId) return
    return subscribeToRound(roundId, setRound, () => {
      setLoadError('Не удалось загрузить лобби. Возможно, вы не участник этого раунда или пропала связь.')
    })
  }, [roundId])

  // Auto-navigate to hole 1 once host starts the round
  useEffect(() => {
    if (round?.status === 'active' && roundId) {
      navigate(`/round/${roundId}/hole/1`, { replace: true })
    }
    if (round?.status === 'finished' && roundId) {
      navigate(`/round/${roundId}/results`, { replace: true })
    }
  }, [round?.status, roundId, navigate])

  if (!round || !roundId) {
    return (
      <div className="screen items-center justify-center px-8 text-center gap-4">
        {loadError ? (
          <>
            <p className="text-error text-body-md">{loadError}</p>
            <Button variant="secondary" onClick={() => navigate('/home', { replace: true })}>
              На главную
            </Button>
          </>
        ) : (
          <p className="text-on-surface-variant text-body-md">Загрузка лобби...</p>
        )}
      </div>
    )
  }

  const isHost = round.hostId === user?.uid
  const joinUrl = `${window.location.origin}/join/${round.lobbyCode}`
  const players = Object.entries(round.players).filter(
    ([uid]) => round.playerIds.includes(uid),
  )

  async function handleStart() {
    if (!isHost) return
    setStarting(true)
    setError(null)
    try {
      await startRound(roundId!)
      // Subscriber effect will navigate everyone to /hole/1
    } catch {
      setError('Не удалось запустить раунд. Попробуйте ещё раз.')
      setStarting(false)
    }
  }

  async function handleLeave() {
    if (!user || !roundId) return
    try { await leaveLobby(roundId, user.uid) } catch { /* ignore */ }
    navigate('/home', { replace: true })
  }

  function copyCode() {
    if (!round) return
    navigator.clipboard?.writeText(round.lobbyCode).catch(() => {})
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }

  function copyLink() {
    navigator.clipboard?.writeText(joinUrl).catch(() => {})
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }

  return (
    <div className="screen pb-6">
      <PageHeader title="Лобби группы" />

      <div className="flex-1 px-5 pt-5 space-y-5 overflow-y-auto">
        <div className="text-center space-y-1">
          <p className="text-label-md text-on-surface-variant uppercase tracking-wider">{round.courseName}</p>
          <p className="text-label-md text-on-surface-variant">{round.totalHoles} лунок</p>
        </div>

        {/* Lobby code */}
        <Card>
          <p className="text-label-md text-on-surface-variant uppercase tracking-[0.15em] font-semibold text-center">
            Код лобби
          </p>
          <button
            type="button"
            onClick={copyCode}
            className="block w-full font-headline font-bold text-display-lg text-primary tracking-[0.3em] mt-2 active:scale-95 transition-transform"
          >
            {round.lobbyCode}
          </button>
          <p className="text-center text-label-md text-on-surface-variant mt-1 inline-flex items-center justify-center gap-1 w-full">
            {copied ? (
              <>
                <Check size={14} strokeWidth={2.5} className="text-primary" /> Скопировано
              </>
            ) : (
              <>
                <Copy size={14} strokeWidth={1.75} /> Тап чтобы скопировать
              </>
            )}
          </p>
        </Card>

        {/* QR */}
        <Card>
          <p className="text-label-md text-on-surface-variant uppercase tracking-[0.15em] font-semibold text-center mb-3">
            Или отсканируйте QR
          </p>
          <div className="flex justify-center bg-surface-container-lowest p-3 rounded-lg">
            <QRCodeSVG value={joinUrl} size={200} level="M" bgColor="#FFFFFF" fgColor="#1A1C1C" />
          </div>
          <button
            type="button"
            onClick={copyLink}
            className="block w-full text-center text-label-lg text-primary font-semibold mt-3 active:scale-95"
          >
            Скопировать ссылку
          </button>
        </Card>

        {/* Players list */}
        <div>
          <div className="flex items-baseline justify-between mb-2 px-1">
            <h3 className="font-headline font-semibold text-title-lg text-on-surface">Игроки</h3>
            <span className="text-label-md text-on-surface-variant">{players.length}</span>
          </div>
          <div className="space-y-2">
            {players.map(([uid, p]) => (
              <Card key={uid}>
                <div className="flex items-center gap-3">
                  <Avatar src={p.avatar} name={p.name} size={40} />
                  <span className="flex-1 font-semibold text-body-md text-on-surface truncate">{p.name}</span>
                  {uid === round.hostId && (
                    <span className="text-label-md font-semibold text-primary bg-primary-container/15 px-2 py-0.5 rounded-full uppercase tracking-wider">
                      Хост
                    </span>
                  )}
                  {uid === user?.uid && uid !== round.hostId && (
                    <span className="text-label-md text-on-surface-variant uppercase tracking-wider">Вы</span>
                  )}
                </div>
              </Card>
            ))}
          </div>
        </div>

        {error && (
          <p className="text-center text-label-lg text-error">{error}</p>
        )}
      </div>

      {/* Actions */}
      <div className="px-5 pb-6 space-y-3">
        {isHost ? (
          <Button icon={Play} onClick={handleStart} disabled={starting || players.length === 0}>
            {starting
              ? 'Запускаем...'
              : `Начать раунд (${players.length} ${pluralRu(players.length, 'игрок', 'игрока', 'игроков')})`}
          </Button>
        ) : (
          <div className="text-center text-body-md text-on-surface-variant py-3">
            Ожидаем хоста...
          </div>
        )}
        <Button variant="secondary" onClick={() => setShowLeaveConfirm(true)}>
          Покинуть лобби
        </Button>
      </div>

      <ConfirmDialog
        open={showLeaveConfirm}
        title="Покинуть лобби?"
        body={isHost ? 'Вы хост — без вас раунд не запустится. Лобби останется доступным по коду, но другим игрокам придётся ждать.' : 'Вы выйдете из этого лобби. Можно вернуться по коду.'}
        confirmLabel="Покинуть"
        cancelLabel="Остаться"
        onConfirm={handleLeave}
        onCancel={() => setShowLeaveConfirm(false)}
      />
    </div>
  )
}
