import {onSchedule} from "firebase-functions/v2/scheduler";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

admin.initializeApp();

const db = admin.firestore();
const FIVE_MINUTES_MS = 5 * 60 * 1000;
const ONE_HOUR_MS = 60 * 60 * 1000;
const TWO_MINUTES_MS = 2 * 60 * 1000; // ハートビートタイムアウト
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
 * lastHeartbeatが2分以上更新されていないconnectedセッションをdisconnectedに更新
 * モニターアプリクラッシュ時などの検知に使用
 * スケジュール: 5分ごとに実行
 */
export const cleanupStaleHeartbeatSessions = onSchedule(
  {
    schedule: "*/5 * * * *",
    timeZone: "Asia/Tokyo",
    region: "asia-northeast1",
  },
  async () => {
    const now = Date.now();
    const cutoffTime = now - TWO_MINUTES_MS;

    try {
      const sessionsSnapshot = await db.collectionGroup("sessions")
        .where("status", "==", "connected")
        .get();

      const docsToUpdate: admin.firestore.QueryDocumentSnapshot[] = [];
      for (const doc of sessionsSnapshot.docs) {
        const data = doc.data();
        const lastHeartbeat = data.lastHeartbeat as
          admin.firestore.Timestamp | undefined;
        if (!lastHeartbeat || lastHeartbeat.toMillis() < cutoffTime) {
          docsToUpdate.push(doc);
        }
      }

      if (docsToUpdate.length > 0) {
        for (let i = 0; i < docsToUpdate.length; i += BATCH_LIMIT) {
          const chunk = docsToUpdate.slice(i, i + BATCH_LIMIT);
          const batch = db.batch();
          for (const doc of chunk) {
            batch.update(doc.ref, {status: "disconnected"});
          }
          await batch.commit();
        }
        console.log(
          `Updated ${docsToUpdate.length} stale heartbeat sessions to disconnected`
        );
      }
    } catch (error) {
      console.error(
        "Error cleaning up stale heartbeat sessions:", error
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
          `onSessionCreated: Updated ${docsToUpdate.length} old sessions to disconnected ` +
          `for user ${monitorUserId} in camera ${cameraId}`
        );
      }
    } catch (error) {
      console.error(
        "onSessionCreated: Error updating old sessions:", error
      );
    }
  }
);
