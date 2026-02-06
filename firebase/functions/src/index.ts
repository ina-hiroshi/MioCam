import * as functions from "firebase-functions/v2";
import * as admin from "firebase-admin";

admin.initializeApp();

const db = admin.firestore();
const FIVE_MINUTES_MS = 5 * 60 * 1000;
const ONE_HOUR_MS = 60 * 60 * 1000;

/**
 * 作成から5分以内に `connected` にならなかったセッションを自動削除
 * スケジュール: 5分ごとに実行
 */
export const cleanupStaleSessions = functions.scheduler
  .timeZone("Asia/Tokyo")
  .onSchedule("*/5 * * * *", async (event) => {
    const now = Date.now();
    const cutoffTime = now - FIVE_MINUTES_MS;

    try {
      // 全カメラのセッションをスキャン
      const camerasSnapshot = await db.collectionGroup("sessions")
        .where("status", "==", "waiting")
        .where("createdAt", "<", admin.firestore.Timestamp.fromMillis(cutoffTime))
        .get();

      const batch = db.batch();
      let deletedCount = 0;

      camerasSnapshot.forEach((doc) => {
        batch.delete(doc.ref);
        deletedCount++;
      });

      if (deletedCount > 0) {
        await batch.commit();
        console.log(`Deleted ${deletedCount} stale sessions`);
      }

      return { deletedCount };
    } catch (error) {
      console.error("Error cleaning up stale sessions:", error);
      throw error;
    }
  });

/**
 * `disconnected` 状態のセッションを1時間後に自動削除
 * スケジュール: 1時間ごとに実行
 */
export const cleanupDisconnectedSessions = functions.scheduler
  .timeZone("Asia/Tokyo")
  .onSchedule("0 * * * *", async (event) => {
    const now = Date.now();
    const cutoffTime = now - ONE_HOUR_MS;

    try {
      // 全カメラのセッションをスキャン
      const sessionsSnapshot = await db.collectionGroup("sessions")
        .where("status", "==", "disconnected")
        .where("createdAt", "<", admin.firestore.Timestamp.fromMillis(cutoffTime))
        .get();

      const batch = db.batch();
      let deletedCount = 0;

      sessionsSnapshot.forEach((doc) => {
        batch.delete(doc.ref);
        deletedCount++;
      });

      if (deletedCount > 0) {
        await batch.commit();
        console.log(`Deleted ${deletedCount} disconnected sessions`);
      }

      return { deletedCount };
    } catch (error) {
      console.error("Error cleaning up disconnected sessions:", error);
      throw error;
    }
  });
