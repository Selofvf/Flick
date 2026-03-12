const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

// Push при новом сообщении
exports.onNewMessage = functions.firestore
  .document("chats/{chatId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    const msg  = snap.data();
    const chatId = context.params.chatId;

    if (!msg) return;

    const senderId   = msg.senderId;
    const senderName = msg.senderName || "Flick";
    const text       = msg.text || "📷 Фото";

    // Получаем участников чата
    const chatDoc = await admin.firestore()
      .collection("chats").doc(chatId).get();
    const members = chatDoc.data()?.members || [];

    // Отправляем уведомление всем кроме отправителя
    const tokens = [];
    for (const uid of members) {
      if (uid === senderId) continue;
      const userDoc = await admin.firestore()
        .collection("users").doc(uid).get();
      const token = userDoc.data()?.fcmToken;
      if (token) tokens.push(token);
    }

    if (tokens.length === 0) return;

    const payload = {
      notification: {
        title: senderName,
        body:  text,
      },
      data: {
        chatId: chatId,
        type:   "message",
      },
      tokens: tokens,
    };

    await admin.messaging().sendEachForMulticast(payload);
  });

// Push при входящем звонке
exports.onIncomingCall = functions.database
  .ref("calls/{chatId}/offer")
  .onCreate(async (snap, context) => {
    const chatId = context.params.chatId;

    // Получаем участников чата
    const chatDoc = await admin.firestore()
      .collection("chats").doc(chatId).get();
    const data    = chatDoc.data();
    const members = data?.members || [];
    const names   = data?.names   || {};

    const tokens = [];
    let callerName = "Кто-то";

    for (const uid of members) {
      const userDoc = await admin.firestore()
        .collection("users").doc(uid).get();
      const userData = userDoc.data();
      if (!userData) continue;
      const token = userData.fcmToken;
      if (token) tokens.push({ uid, token });
    }

    if (tokens.length === 0) return;

    // Определяем имя звонящего из names
    for (const [uid, name] of Object.entries(names)) {
      callerName = name;
      break;
    }

    const sends = tokens.map(({ token }) =>
      admin.messaging().send({
        token,
        notification: {
          title: "📞 Входящий звонок",
          body:  `${callerName} звонит вам`,
        },
        data: {
          chatId: chatId,
          type:   "call",
        },
        android: {
          priority: "high",
          notification: {
            channelId: "flick_calls",
            sound:     "default",
          },
        },
      })
    );

    await Promise.allSettled(sends);
  });