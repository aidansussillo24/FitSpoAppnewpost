# FitSpoAppnewpost

![IMG_6308](https://github.com/user-attachments/assets/83c3bad3-0a41-43bd-9b5a-ed3f85c27329)


## Firestore setup

Hot post queries sort by both `timestamp` and `likes`. Firestore needs a
composite index for these fields. Create an index on the `posts` collection with
`timestamp` descending and `likes` descending, then wait for the index to finish
building. Once done, rerun the app and it will display today's posts sorted by
likes.


## Activity

A simple Activity screen lists your notifications. Access it from the bell icon in the top-left corner of the Home view. You will be notified when someone comments on or likes your posts.
