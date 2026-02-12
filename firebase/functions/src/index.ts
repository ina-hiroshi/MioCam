import {onSchedule} from "firebase-functions/v2/scheduler";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

admin.initializeApp();

const db = admin.firestore();
const ONE_HOUR_MS = 60 * 60 * 1000;
const FIFTEEN_MINUTES_MS = 15 * 60 * 1000;
const BATCH_LIMIT = 500; // Firestore batch操作の上限

/**
 * Firestore batch操作を500件ごとにチャンク分割して実行
 * @param {admin.firestore.QueryDocumentSnapshot[]} docs 削除対象のドキュメント配列
 * @return {Promise<number>} 削除されたドキュメント数
 */
async function deleteInBatches(
  docs: admin.firestore.QueryDocumentSnapshot[]
): Promise<number> {
  let totalDeleted = 0;
  const chunks: admin.firestore.QueryDocumentSnapshot[][] = [];

  // 500件ごとにチャンクに分割
  for (let i = 0; i < docs.length; i += BATCH_LIMIT) {
    chunks.push(docs.slice(i, i + BATCH_LIMIT));
  }

  // 各チャンクを順次処理
  for (const chunk of chunks) {
    const batch = db.batch();
    chunk.forEach((doc) => {
      batch.delete(doc.ref);
    });
    await batch.commit();
    totalDeleted += chunk.length;
  }

  return totalDeleted;
}

/**
 * 作成から15分以内に `connected` にならなかったセッションを自動削除
 * スケジュール: 15分ごとに実行
 */
export const cleanupStaleSessions = onSchedule(
  {
    schedule: "*/15 * * * *",
    timeZone: "Asia/Tokyo",
    region: "asia-northeast1",
  },
  async () => {
    const now = Date.now();
    const cutoffTime = now - FIFTEEN_MINUTES_MS;

    try {
      // 全カメラのセッションをスキャン
      const sessionsSnapshot = await db.collectionGroup("sessions")
        .where("status", "==", "waiting")
        .where("createdAt", "<",
          admin.firestore.Timestamp.fromMillis(cutoffTime))
        .get();

      const deletedCount = await deleteInBatches(sessionsSnapshot.docs);

      if (deletedCount > 0) {
        console.log(`Deleted ${deletedCount} stale sessions`);
      }
    } catch (error) {
      console.error("Error cleaning up stale sessions:", error);
      throw error;
    }
  }
);

/**
 * 親カメラがオフラインかつlastSeenAtが1時間以上前の孤立したconnectedセッションを削除
 * カメラ・モニター両方クラッシュ時の残存セッションをクリーンアップ
 * スケジュール: 1時間ごとに実行
 */
export const cleanupOrphanedSessions = onSchedule(
  {
    schedule: "0 * * * *",
    timeZone: "Asia/Tokyo",
    region: "asia-northeast1",
  },
  async () => {
    const now = Date.now();
    const cutoffTime = now - ONE_HOUR_MS;

    try {
      const sessionsSnapshot = await db.collectionGroup("sessions")
        .where("status", "==", "connected")
        .get();

      const docsToDelete: admin.firestore.QueryDocumentSnapshot[] = [];
      for (const doc of sessionsSnapshot.docs) {
        // 親カメラドキュメントを取得 (cameras/{cameraId}/sessions/{sessionId})
        const cameraRef = doc.ref.parent.parent;
        if (!cameraRef) continue;

        const cameraDoc = await cameraRef.get();
        if (!cameraDoc.exists) continue;

        const cameraData = cameraDoc.data();
        const isOnline = cameraData?.isOnline === true;
        const lastSeenAt = cameraData?.lastSeenAt as
          admin.firestore.Timestamp | undefined;

        // 親カメラがオフライン AND lastSeenAtが1時間以上前 → 孤立セッションとして削除
        if (!isOnline && lastSeenAt && lastSeenAt.toMillis() < cutoffTime) {
          docsToDelete.push(doc);
        }
      }

      if (docsToDelete.length > 0) {
        const deletedCount = await deleteInBatches(docsToDelete);
        console.log(
          `Deleted ${deletedCount} orphaned sessions (camera offline >1h)`
        );
      }
    } catch (error) {
      console.error(
        "Error cleaning up orphaned sessions:", error
      );
      throw error;
    }
  }
);

/**
 * `disconnected` 状態のセッションを1時間後に自動削除
 * スケジュール: 1時間ごとに実行
 */
export const cleanupDisconnectedSessions = onSchedule(
  {
    schedule: "0 * * * *",
    timeZone: "Asia/Tokyo",
    region: "asia-northeast1",
  },
  async () => {
    const now = Date.now();
    const cutoffTime = now - ONE_HOUR_MS;

    try {
      // 全カメラのセッションをスキャン
      const sessionsSnapshot = await db.collectionGroup("sessions")
        .where("status", "==", "disconnected")
        .where("createdAt", "<",
          admin.firestore.Timestamp.fromMillis(cutoffTime))
        .get();

      const deletedCount = await deleteInBatches(sessionsSnapshot.docs);

      if (deletedCount > 0) {
        console.log(`Deleted ${deletedCount} disconnected sessions`);
      }
    } catch (error) {
      console.error("Error cleaning up disconnected sessions:", error);
      throw error;
    }
  }
);

/**
 * セッション作成時に、同じユーザーの同じカメラの古いセッションを disconnected に更新
 * 削除ではなくステータス更新にすることで、カメラ側の処理と競合しない
 * カメラの observeConnectedSessions は status==connected のみ返すため、更新により検知される
 */
export const onSessionCreated = onDocumentCreated(
  {
    document: "cameras/{cameraId}/sessions/{sessionId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const newSessionData = snapshot.data();
    const monitorUserId = newSessionData.monitorUserId as string;
    const newSessionId = event.params.sessionId;
    const cameraId = event.params.cameraId;

    if (!monitorUserId) return;

    try {
      // 同じカメラ内で同じ monitorUserId の他のセッションを検索
      const existingSessions = await db
        .collection("cameras").doc(cameraId)
        .collection("sessions")
        .where("monitorUserId", "==", monitorUserId)
        .get();

      // 新しいセッション以外を disconnected に更新（削除は競合を避けるため行わない）
      const docsToUpdate = existingSessions.docs.filter(
        (doc: admin.firestore.QueryDocumentSnapshot) =>
          doc.id !== newSessionId
      );

      if (docsToUpdate.length > 0) {
        // Firestore batch上限（500件）に合わせてチャンク分割
        for (let i = 0; i < docsToUpdate.length; i += BATCH_LIMIT) {
          const chunk = docsToUpdate.slice(i, i + BATCH_LIMIT);
          const batch = db.batch();
          for (const doc of chunk) {
            batch.update(doc.ref, {status: "disconnected"});
          }
          await batch.commit();
        }
        console.log(
          `onSessionCreated: Updated ${docsToUpdate.length} old sessions ` +
          `to disconnected for user ${monitorUserId} in camera ${cameraId}`
        );
      }
    } catch (error) {
      console.error(
        "onSessionCreated: Error updating old sessions:", error
      );
    }
  }
);
