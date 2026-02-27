importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyCOtOZmZU_8nhg7RF5C5LW7cq-dpOVr-P4",
  authDomain: "gitlauk-e752f.firebaseapp.com",
  projectId: "gitlauk-e752f",
  storageBucket: "gitlauk-e752f.firebasestorage.app",
  messagingSenderId: "568002325053",
  appId: "1:568002325053:web:d7c078cff8a6e507b01854",
  measurementId: "G-KVDNB8S399",
});

const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage((message) => {
  console.log("onBackgroundMessage", message);
  const notificationTitle = message.notification?.title || "New Notification";
  const notificationOptions = {
    body: message.notification?.body || "",
    icon: "/icons/Icon-192.png",
  };
  return self.registration.showNotification(notificationTitle, notificationOptions);
});
