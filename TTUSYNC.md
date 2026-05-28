To sync between Hoshi Reader and ッツ Reader, a Google Cloud project is required.

# Setting up the Google Cloud project
1. Login to a Google account.
2. Navigate to https://console.cloud.google.com/projectselector2/home/dashboard.
3. Press on `Create project` in the top right corner.

<img src="Pictures/gdrive_1.png" width="80%" alt="">

4. Choose any name for your project and Press on `Create`.

<img src="Pictures/gdrive_2.png" width="80%" alt="">

5. In the left sidebar, hover over `APIs & Services`, then choose `Enabled APIs & services`.

<img src="Pictures/gdrive_3.png" width="80%" alt="">

6. Press on `Enable APIs & services`.

<img src="Pictures/gdrive_4.png" width="80" alt="">

7. Search for Google Drive and choose `Google Drive API`.
8. Press `Enable`.

<img src="Pictures/gdrive_5.png" width="80%" alt="">

9. You should be redirected, in the left bar choose `OAuth consent screen`.

<img src="Pictures/gdrive_6.png" width="80%" alt="">

10. Press on `Get started` in the middle.

<img src="Pictures/gdrive_7.png" width="80%" alt="">

11. Choose anything for the `App name` and select your email as the `User support email`, press on next.
12. As the `Audience` choose `External`.
13. As the `Contact information` just type in your email address.
14. Tick `I agree`, press on `Continue` and then `Create`.

<img src="Pictures/gdrive_8.png" width="80%" alt="">

15. In the left bar, navigate to `Data Access` and press on `Add or remove scopes`.

<img src="Pictures/gdrive_9.png" width="80%" alt="">

16. Look for the `.../auth/drive.file` scope and tick the box, press on `Update` at the bottom.

<img src="Pictures/gdrive_10.png" width="80%" alt="">

17. Make sure it's listed under `Your non-sensitive scopes` and press on `Save` at the bottom.

<img src="Pictures/gdrive_11.png" width="80%" alt="">

18. in the left side bar navigate to audience, and press on publish then confirm.

<img src="Pictures/gdrive_12.png" width="80%" alt="">

You will need to create clients under the **same** project for each platform that you want to use. 

Navigate to clients and press on create client.

<img src="Pictures/gdrive_13.png" width="80%" alt="">

## ッツ
1. Choose `Web application` as the `Application type` and choose any name.
2. Click on `Add URI` under `Authorized JavaScript origins` and add `https://reader.ttsu.app` and `https://ttu-ebook.web.app`
3. Click on `Add URI` under `Authorized redirect URIs` and add `https://reader.ttsu.app/auth` and `https://ttu-ebook.web.app/auth`
4. Press on `Create`.

<img src="Pictures/gdrive_14.png" width="80%" alt="">

5. Copy the `Client ID`, and the `Client secret` and save it somewhere. I also recommended downloading the JSON and saving it in case you need the credentials later. You can find Client ID and secret by looking for "client_id" and "client_secret" in the file. 

<img src="Pictures/gdrive_15.png" width="80%" alt="">

<img src="Pictures/gdrive_16.png" width="80%" alt="">

6. Open ッツ and navigate to `Settings` -> `Data`. Next to `Storage sources` press on `+ Add`
7. Choose any name and for `Client ID` and `Client Secret` paste in the values from the step before.
8. Choose a password and optionally tick `Store in Password Manager` or `Disable Password Encryption` entirely.
9. Tick `Is Sync Target` and `Is Source Default` at the top and press on save

<img src="Pictures/gdrive_17.png" width="80%" alt="">

10. Exit Settings and navigate back to the books screen.
11. At the top, choose the `GDrive` source

<img src="Pictures/gdrive_18.png" width="80%" alt="">

12. A Google Sign-in window will open, choose your Google account and authorize the app.

<img src="Pictures/gdrive_19.png" width="80%" alt="">

## iOS
1. Choose iOS as the `Application type` and choose any name
2. Type in `de.manhhao.hoshi` as the Bundle ID
3. Press on `Create` and copy the `Client ID`

<img src="Pictures/gdrive_20.png" width="80%" alt="">

4. Open Hoshi Reader on your device and navigate to `Advanced` -> `ッツ Sync`
5. Paste in the `Client ID` and tap on `Connect Google Drive`
6. Log-in to your Google account and authorize the app.

<img src="Pictures/gdrive_21.png" width="40%" alt="">

## Android
1. Choose TVs and Limited Input devices as the `Application type` and choose any name
2. Copy the `Client ID`, and the `Client secret` and save it somewhere. I also recommended downloading the JSON and saving it in case you need the credentials later. You can find Client ID and secret by looking for "client_id" and "client_secret" in the file. (see ッツ section)
3. Copy the authorization code from the app and go to the domain (you might have to use a different device).
4. Log-in to your Google account and authorize the app.

# Syncing

## ッツ

To sync a book in ッツ you can either choose to manually sync (recommended) or enable auto sync.
Regardless of the syncing method, you should **ALWAYS** use the Browser source when reading.

<img src="Pictures/gdrive_22.png" width="80%" alt="">

### Auto Sync

In Settings -> Data select `All` for `Auto Import/Export`

<img src="Pictures/gdrive_23.png" width="80%" alt="">

### Manual

In Settings -> Data, I recommend choosing "Overwrite" for "Import/Export Behavior" to prevent being unable to overwrite local/remote bookmarks because you loaded into the book.

#### Syncing to Google Drive
To sync a book to Google Drive, make sure you're using the browser source.

Select the book and press on the cloud symbol at the top. 

<img src="Pictures/gdrive_24.png" width="80%" alt="">

Tick the data you want to sync, Hoshi Reader supports syncing book data, bookmarks, statistics and audiobook progress. Book Data only has to be synced once and can be unticked in subsequent syncs.

You will want to sync after each reading session, or when you want to swap devices.

<img src="Pictures/gdrive_25.png" width="80%" alt="">

#### Syncing from Google Drive

To sync back a book from Google Drive after you've synced to Google Drive from a different device, simply swap to the GDrive source and follow the exact same steps but choose `Browser DB`.

**SWAP BACK TO THE BROWSER SOURCE TO READ**

## Hoshi Reader

Screenshots will show the iOS version, steps for the Android version are similar.

Make sure sync is set up and you're connected. To enable syncing for statistics and audiobook progress, enable the options in `Advanced` -> `ッツ Sync` or in their respective settings menus.

<img src="Pictures/gdrive_26.png" width="40%" alt="">

You can use Auto Sync in Hoshi Reader which will periodically queue syncs while you're reading or on specific triggers like exiting the reader or backgrounding the app. If you foreground after the app was backgrounded for an extended period of time, it will automatically try to pull a newer bookmark from Google Drive. Auto Syncing will slightly slow down opening books.

If you prefer manually syncing. You can long press a book in the library and tap on sync. If the direction is set to auto, it will try to auto resolve the newer bookmark and either import or export. If you set direction to manual in settings, you can choose the sync direction.

<img src="Pictures/gdrive_27.png" width="40%" alt="">