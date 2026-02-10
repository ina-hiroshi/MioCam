import {onSchedule} from "firebase-functions/v2/scheduler";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

admin.initializeApp();

const db = admin.firestore();
const FIVE_MINUTES_MS = 5 * 60 * 1000;
const ONE_HOUR_MS = 60 * 60 * 1000;
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
 * 作成から5分以内に `connected` にならなかったセッションを自動削除
 * スケジュール: 5分ごとに実行
 */
export const cleanupStaleSessions = onSchedule(
  {
    schedule: "*/5 * * * *",
    timeZone: "Asia/Tokyo",
    region: "asia-northeast1",
  },
  async () => {
    const now = Date.now();
    const cutoffTime = now - FIVE_MINUTES_MS;

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
 * セッション作成時に、同じユーザーの同じカメラの古いセッションを自動削除
 * 新しいセッションが作成されると、同じ monitorUserId の他のセッションを削除する
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

      // 新しいセッション以外を削除
      const docsToDelete = existingSessions.docs.filter(
        (doc: admin.firestore.QueryDocumentSnapshot) =>
          doc.id !== newSessionId
      );

      if (docsToDelete.length > 0) {
        const deletedCount = await deleteInBatches(
          docsToDelete as admin.firestore.QueryDocumentSnapshot[]
        );
        console.log(
          `onSessionCreated: Deleted ${deletedCount} old sessions ` +
          `for user ${monitorUserId} in camera ${cameraId}`
        );
      }
    } catch (error) {
      console.error(
        "onSessionCreated: Error deleting old sessions:", error
      );
    }
  }
);
