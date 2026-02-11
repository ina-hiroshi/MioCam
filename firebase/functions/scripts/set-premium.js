/**
 * 指定ユーザーをプレミアムプランに設定するスクリプト
 * 実行: node scripts/set-premium.js <userId>
 *
 * 認証: GOOGLE_APPLICATION_CREDENTIALS をサービスアカウントキーパスに設定するか、
 *       gcloud auth application-default login を実行してください。
 */

const admin = require('firebase-admin');

const userId = process.argv[2];
if (!userId) {
  console.error('Usage: node scripts/set-premium.js <userId>');
  process.exit(1);
}

async function main() {
  if (!admin.apps.length) {
    admin.initializeApp({ projectId: 'miocam-9bf20' });
  }
  const db = admin.firestore();

  const subscriptionRef = db
    .collection('users')
    .doc(userId)
    .collection('subscription')
    .doc('current');

  const data = {
    plan: 'premium',
    expiresAt: null, // 無期限（任意で Timestamp を設定可能）
    originalTransactionId: 'manual-set-' + Date.now(),
  };

  await subscriptionRef.set(data, { merge: true });
  console.log(`✅ User ${userId} をプレミアムプランに設定しました`);
}

main().catch((err) => {
  console.error('エラー:', err.message);
  process.exit(1);
});
