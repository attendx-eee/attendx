/**
 * AttendX push delivery.
 *
 * Everything in the app already writes a document to `notifications`
 * when it wants to tell someone something — a faculty member saving a
 * period, an admin correcting a day, a CR cancelling a class. Those
 * documents were only ever seen by a Firestore listener, which stops
 * running the moment the app is killed. So a student marked absent at
 * 2pm found out whenever they next opened the app.
 *
 * This turns each new document into an actual push. Nothing else in the
 * app had to change: the trigger sits on the collection that was
 * already being written to.
 */

const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {setGlobalOptions} = require("firebase-functions/v2");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

initializeApp();

// Mumbai — same region as the Firestore database (asia-south1). A
// function in another region would add a cross-continent round trip to
// every read it does.
setGlobalOptions({
  region: "asia-south1",
  maxInstances: 10,
});

const db = getFirestore();

/** Collections that can hold an account, in the order they're checked. */
const ACCOUNT_COLLECTIONS = ["students", "faculty_accounts", "admin"];

/**
 * Finds a uid's device tokens.
 *
 * Three collections because the app splits accounts by role. Returns an
 * empty array rather than throwing when nothing is found: a
 * notification for an account that has never opened the app is normal,
 * not an error.
 *
 * @param {string} uid Account id.
 * @return {Promise<{ref: FirebaseFirestore.DocumentReference,
 *                    tokens: string[]}|null>}
 */
async function findTokens(uid) {
  for (const name of ACCOUNT_COLLECTIONS) {
    const ref = db.collection(name).doc(uid);
    const snap = await ref.get();

    if (snap.exists) {
      const tokens = snap.get("fcmTokens");
      return {ref, tokens: Array.isArray(tokens) ? tokens : []};
    }
  }

  return null;
}

exports.sendNotificationPush = onDocumentCreated(
    "notifications/{notificationId}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const data = snap.data() || {};
      const uid = data.studentUid;

      if (!uid) {
        console.log("No studentUid on notification; nothing to send.");
        return;
      }

      const account = await findTokens(uid);

      if (!account || account.tokens.length === 0) {
        console.log(`No device tokens for ${uid}.`);
        return;
      }

      const title = data.title || "AttendX";
      const body = data.body || "";

      const response = await getMessaging().sendEachForMulticast({
        tokens: account.tokens,

        // Both a notification block and a data block. The notification
        // block is what Android draws when the app is dead — the Dart
        // isolate isn't guaranteed to run in time to draw it itself.
        // The data block is what the app reads when it *is* running, so
        // a foreground message is styled by the app rather than by the
        // system.
        notification: {title, body},

        data: {
          title,
          body,
          category: String(data.category || "general"),
          action: String(data.action || ""),
          notificationId: event.params.notificationId,
        },

        android: {
          priority: "high",
          notification: {
            // Must match the channel created in
            // LocalNotificationService.init and declared in the
            // manifest, or API 26+ discards the message in silence.
            channelId: "realtime_alerts",
            // Collapses repeats of the same subject rather than
            // stacking six identical absence alerts.
            tag: String(data.category || "general"),
          },
        },

        apns: {
          payload: {aps: {sound: "default", badge: 1}},
        },
      });

      // Tokens die constantly — app uninstalled, data cleared, phone
      // restored to a new device. Left in place they make every future
      // send report partial failure, and the array grows without limit.
      const dead = [];
      response.responses.forEach((result, i) => {
        if (result.success) return;

        const code = result.error && result.error.code;
        if (
          code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token" ||
          code === "messaging/invalid-argument"
        ) {
          dead.push(account.tokens[i]);
        } else {
          console.warn(`Send failed for ${uid}: ${code}`);
        }
      });

      if (dead.length > 0) {
        await account.ref.update({
          fcmTokens: FieldValue.arrayRemove(...dead),
        });
        console.log(`Pruned ${dead.length} dead token(s) for ${uid}.`);
      }

      console.log(
          `Pushed to ${uid}: ${response.successCount} ok, ` +
        `${response.failureCount} failed.`,
      );
    },
);
