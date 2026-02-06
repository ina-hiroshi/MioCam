import {onSchedule} from "firebase-functions/v2/scheduler";
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
