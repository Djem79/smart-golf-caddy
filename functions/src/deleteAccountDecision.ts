// Чистая логика решения «что делать с раундом при удалении аккаунта» —
// вынесена из deleteAccount (index.ts) специально для юнит-тестов: сама
// callable трогает Firestore/Auth и её нельзя протестировать без эмулятора,
// а эта функция — чистая (playerIds/hostId/uid → решение), без побочных
// эффектов.
//
// ВАЖНО: решение НЕ зависит от status раунда. Ранняя версия форсировала
// status → 'finished' для раунда, где удаляемый был хостом lobby/active —
// ревью показало, что это ломает третьих лиц: onRoundFinished рассылает
// email ВСЕМ playerIds на любой флип в 'finished' (в том числе
// программный) с промежуточным счётом и жжёт их дневную квоту, а
// recordShot после этого перманентно отклоняет ещё не доставленные удары
// соигроков из офлайн-очереди (веб/iOS дропают их с rollback без способа
// повторить — раунд уже "завершён"). Поэтому теперь status раунда не
// трогается вообще ни в одной ветке; вместо принудительного завершения
// раунда роль хоста передаётся первому оставшемуся участнику, чтобы
// START/FINISH (host-only действия) остались доступны живому игроку.

export interface RoundDeletionInput {
  playerIds: string[]
  hostId: string
  /** uid аккаунта, который удаляется. */
  uid: string
}

export type RoundDeletionDecision =
  // Раунд удаляется целиком — после удаления uid других реальных
  // участников не осталось (соло-раунд, либо playerIds состоял из
  // uid с дублями и больше никого).
  | { action: 'delete' }
  // Раунд остаётся, слот uid обезличивается. newHostId присутствует,
  // только если удаляемый был хостом и роль передаётся первому
  // оставшемуся участнику (playerIds сохраняет исходный порядок).
  | { action: 'anonymize'; newHostId?: string }

export function decideRoundDeletion({ playerIds, hostId, uid }: RoundDeletionInput): RoundDeletionDecision {
  // Убираем ВСЕ вхождения uid (playerIds теоретически может содержать
  // дубликаты из старых данных) — остаются только другие реальные игроки,
  // в исходном порядке.
  const others = playerIds.filter(id => id !== uid)

  if (others.length === 0) {
    return { action: 'delete' }
  }

  if (hostId === uid) {
    return { action: 'anonymize', newHostId: others[0] }
  }

  return { action: 'anonymize' }
}
