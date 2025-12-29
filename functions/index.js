const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

// Listens for new documents in the notifications collection
exports.sendNotification = functions.firestore
  .document("seasons/{seasonId}/notifications/{notifId}")
  .onCreate(async (snapshot, context) => {
    const data = snapshot.data();
    const seasonId = context.params.seasonId;

    // The message payload
    const payload = {
      notification: {
        title: data.title,
        body: data.body,
        sound: "default",
      },
      data: {
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        seasonId: seasonId,
        type: data.type || "INFO",
      },
    };

    // Send to topic
    return admin.messaging().sendToTopic(`season_${seasonId}`, payload);
  });