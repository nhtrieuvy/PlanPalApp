importScripts('https://www.gstatic.com/firebasejs/12.3.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.3.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyD1GIETwZj5CNGQtZR2CPqDCkCYLZ6SZrc',
  appId: '1:539351209558:web:0bc0dce41f915f15f88df7',
  messagingSenderId: '539351209558',
  projectId: 'alapp-ffa74',
  authDomain: 'alapp-ffa74.firebaseapp.com',
  storageBucket: 'alapp-ffa74.firebasestorage.app'
});

const messaging = firebase.messaging();

// Firebase displays notification payloads automatically. Data-only messages
// need an explicit notification while the application is in the background.
messaging.onBackgroundMessage((payload) => {
  if (payload.notification) return;
  const data = payload.data || {};
  self.registration.showNotification(data.title || 'PlanPal', {
    body: data.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: {
      route: data.route || '/notifications'
    }
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const route = event.notification.data?.route || '/notifications';
  const targetUrl = new URL(route, self.location.origin).href;
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
      for (const client of windows) {
        if ('focus' in client) {
          client.navigate(targetUrl);
          return client.focus();
        }
      }
      return clients.openWindow ? clients.openWindow(targetUrl) : undefined;
    })
  );
});
