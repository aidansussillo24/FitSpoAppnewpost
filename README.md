# FitSpoAppnewpost

![photoforgit](https://github.com/user-attachments/assets/9d12290a-02ee-4945-9f72-3ea6b0aa2952)

## Firestore setup

Hot post queries sort by both `timestamp` and `likes`. Firestore needs a
composite index for these fields. Create an index on the `posts` collection with
`timestamp` descending and `likes` descending, then wait for the index to finish
building. Once done, rerun the app and it will display today's posts sorted by
likes.

