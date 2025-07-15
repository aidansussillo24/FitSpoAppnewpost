import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import algoliasearch from 'algoliasearch';

admin.initializeApp();

const ALGOLIA_APP_ID = '6WFE31B7U3';
const ALGOLIA_ADMIN_KEY = functions.config().algolia.key;
const client = algoliasearch(ALGOLIA_APP_ID, ALGOLIA_ADMIN_KEY);
const index = client.initIndex('posts');

const settingsPromise = index.setSettings({
  searchableAttributes: ['caption', 'hashtags', 'username'],
  customRanking: ['desc(timestamp)', 'desc(likes)'],
});

export const syncPostToAlgolia = functions.firestore
  .document('posts/{postId}')
  .onWrite(async (change, context) => {
    await settingsPromise;

    if (!change.after.exists) {
      await index.deleteObject(context.params.postId);
      return;
    }

    const data = change.after.data() || {};
    const postId = context.params.postId;

    const record = {
      objectID: postId,
      id: postId,
      caption: data.caption || '',
      hashtags: (data.hashtags || []).map((h: string) => h.toLowerCase()),
      username: data.username || '',
      imageURL: data.imageURL || '',
      timestamp: data.timestamp ? data.timestamp.toMillis() : Date.now(),
      likes: data.likes || 0,
    };

    await index.saveObject(record);
  });
