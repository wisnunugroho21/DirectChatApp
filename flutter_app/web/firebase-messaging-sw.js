// Browser push requires this small service worker; all application UI is Flutter.
importScripts('firebase-config.js');
if (self.FIREBASE_CONFIG) {
  self.addEventListener('notificationclick', event => {
    event.notification.close();
    event.stopImmediatePropagation();
    const data = event.notification.data?.FCM_MSG?.data || event.notification.data || {};
    const url = new URL('./', self.location.href);
    if (data.senderUsername) url.searchParams.set('sender', data.senderUsername);
    event.waitUntil(clients.openWindow(url.href));
  });
  importScripts('https://www.gstatic.com/firebasejs/12.9.0/firebase-app-compat.js');
  importScripts('https://www.gstatic.com/firebasejs/12.9.0/firebase-messaging-compat.js');
  firebase.initializeApp(self.FIREBASE_CONFIG);
  firebase.messaging().onBackgroundMessage(async payload => {
    const data = payload.data || {};
    if (data.type === 'call-cancelled') {
      for (const notification of await self.registration.getNotifications({tag: 'call-' + data.callId})) notification.close();
      return;
    }
    // Firebase displays notification payloads itself.
    if (payload.notification) return;
    return self.registration.showNotification(data.title || 'TMS Connect', {
      body: data.body || '', icon: '/icons/Icon-192.png',
      tag: data.type === 'call' ? 'call-' + data.callId : 'chat-' + data.conversationId,
      data: data
    });
  });
}


