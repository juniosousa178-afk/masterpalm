import { initializeApp, getApps, FirebaseApp } from "firebase/app";
import { getFirestore } from "firebase/firestore";

const firebaseConfig = {
  apiKey: "AIzaSyBPRazC3wOs-x7IdatMy26Dr81pEi4Xz44",
  appId: "1:950139833317:web:4f94d4108daf8ab31ebd0c",
  messagingSenderId: "950139833317",
  projectId: "masterpalm-58c46",
  authDomain: "masterpalm-58c46.firebaseapp.com",
  storageBucket: "masterpalm-58c46.appspot.com",
  measurementId: "G-0F0ZRT1S6G",
};

let app: FirebaseApp;

if (getApps().length === 0) {
  app = initializeApp(firebaseConfig);
} else {
  app = getApps()[0] as FirebaseApp;
}

export const db = getFirestore(app);
