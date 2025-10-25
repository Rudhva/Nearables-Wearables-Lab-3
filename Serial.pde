// -------------------------
// Serial Input
// -------------------------
String readSerialMessage() {
  // Returns the latest full line received from serial
  return latestSerialMessage;
}

void cleanImages() {
  String folderPath = sketchPath("data/library");

  String[] cmd = {
    "/bin/bash",
    "-c",
    "magick mogrify -transparent white '" + folderPath + "/*.png'"
  };

  try {
    println("Running ImageMagick command...");
    Process process = Runtime.getRuntime().exec(cmd);
    process.waitFor();
    println("PNGs processed in-place in 'data/library'.");
  }
  catch (Exception e) {
    // ok to ignore if ImageMagick not installed
    // e.printStackTrace();
  }
}

void serialEvent(Serial p) {
  String input = p.readStringUntil('\n');
  if (input != null) {
    tap = true;
    input = input.trim();
    latestSerialMessage = input.replaceAll("^(\\d+)\\s*(\\w).*", "$1$2"); //number + first letter without spaces
    println("SERIAL: " + latestSerialMessage);
    processSerialMessage(latestSerialMessage);
    latestSerialMessage = "";
  } else {
    tap = false;
  }
}

void processSerialMessage(String msg) {
  if (msg == null || msg.length() == 0) return;
  boolean okKey = false;

  // --- Flex sensor input (F) ---
  if ("F".equals(msg)) {
    if (Fn) {
      // Start selecting the left menu items
      mode = MODE_SELECT_OBJ;
      selectedObjIndex = 0;
      println("Entering MODE_SELECT_OBJ via F+Fn");
    } else {
      // Select next image to place; if already at last image, go to category selection
      if (mode == MODE_PICK_IMG) {
        mode = MODE_PICK_CAT;
      } else {
        mode = MODE_PICK_IMG;
      }
    }
  }


  // --- Fn toggle ---
  if ("6P".equals(msg)) {
    Fn = true;
    return;
  }
  if ("6R".equals(msg)) {
    Fn = false;
    return;
  }

  // --- Undo / Redo (9P) ---
  if ("9P".equals(msg) && !Fn) {
    if (undoStack.size() > 0) {
      ignoreNextPush = true;
      redoStack.add(copyObjectsList(objects));
      if (redoStack.size() > maxHistory) redoStack.remove(0);
      objects = undoStack.remove(undoStack.size() - 1);
      selectedObjIndex = objects.size() - 1;
      ignoreNextPush = false;
    }
    return;
  }

  if ("9P".equals(msg) && Fn) {
    if (redoStack.size() > 0) {
      ignoreNextPush = true;
      undoStack.add(copyObjectsList(objects));
      if (undoStack.size() > maxHistory) undoStack.remove(0);
      objects = redoStack.remove(redoStack.size() - 1);
      selectedObjIndex = objects.size() - 1;
      ignoreNextPush = false;
    }
    return;
  }

  // --- Open selection mode (10P without Fn) ---
  if ("10P".equals(msg) && !Fn) {
    mode = MODE_SELECT_OBJ;
    selectedObjIndex = 0;
    println("Entering MODE_SELECT_OBJ");
    return;
  }

  // --- Open save menu (10P with Fn) ---
  if ("10P".equals(msg) && Fn) {
    showMenu = true;
    typingFilename = false;
    menuX = (width - menuW) / 2;
    menuY = (height - menuH) / 2;
    println("Opened Save/Load Menu");
    return;
  }


  // --- OK button (5P = ENTER) ---
  if ("5P".equals(msg)) {
    okKey = true;

    switch (mode) {
    case MODE_PICK_BG:
      if (bgFilenames.size() > 0) {
        setBackgroundFromPath(bgFilenames.get(currentBgIndex));
        mode = MODE_PICK_CAT;
      }
      return;

    case MODE_PICK_CAT:
      currentImgIndex = 0;
      mode = MODE_PICK_IMG;
      return;

    case MODE_PICK_IMG:
      {
        String cat = CATALOGS[currentCatIndex];
        ArrayList<String> list = catFiles.get(cat);
        if (list == null || list.size() == 0) return;

        String rel = list.get(currentImgIndex);
        PImage im = imgLibrary.get(rel);
        if (im == null) im = loadImage(rel);

        float cx = marginLeft + (width - marginLeft - marginRight) / 2.0;
        float cy = marginTop  + (height - bannerHeight - marginTop - marginBottom) / 2.0;

        pushUndo();
        String name = makeUniqueName(rel);
        objects.add(new DrawingObject(this, im, cx, cy, 1.0, 0, rel, name));
        selectedObjIndex = objects.size() - 1;
        mode = MODE_MOVE_OBJ;
        return;
      }

    case MODE_MOVE_OBJ:
      if (Fn) {
        deleteSelectedTrack();
      } else {
        mode = MODE_PICK_IMG; // Otherwise, just switch back
      }
      return;

    case MODE_SELECT_OBJ:
      mode = MODE_MOVE_OBJ;
      return;
    }


    return;
  }

  // --- Movement / navigation (arrow equivalents) ---
  boolean navUp    = "1P".equals(msg);
  boolean navRight = "2P".equals(msg);
  boolean navDown  = "3P".equals(msg);
  boolean navLeft  = "4P".equals(msg);

  // --- Rotation / Scale (7P / 8P) ---
  boolean scaleKey = "7P".equals(msg);
  boolean rotKey   = "8P".equals(msg);

  // --- Handle based on mode ---
  switch (mode) {
  case MODE_SELECT_OBJ:
    if (objects.size() == 0) return;
    if (navUp) {
      selectedObjIndex = (selectedObjIndex + 1 + objects.size()) % objects.size();
      return;
    }
    if (navDown) {
      selectedObjIndex = (selectedObjIndex - 1 + objects.size()) % objects.size();
      return;
    }
    if (okKey) {
      mode = MODE_MOVE_OBJ;
      return;
    }
    break;

  case MODE_PICK_BG:
    if (bgFilenames.size() == 0) return;
    if (navLeft) {
      currentBgIndex = (currentBgIndex - 1 + bgFilenames.size()) % bgFilenames.size();
      return;
    }
    if (navRight) {
      currentBgIndex = (currentBgIndex + 1) % bgFilenames.size();
      return;
    }
    break;

  case MODE_PICK_CAT:
    if (navLeft) {
      currentCatIndex = (currentCatIndex - 1 + CATALOGS.length) % CATALOGS.length;
      return;
    }
    if (navRight) {
      currentCatIndex = (currentCatIndex + 1) % CATALOGS.length;
      return;
    }
    break;

  case MODE_PICK_IMG:
    {
      String cat = CATALOGS[currentCatIndex];
      ArrayList<String> list = catFiles.get(cat);
      if (list == null || list.size() == 0) return;
      if (navLeft) {
        currentImgIndex = (currentImgIndex - 1 + list.size()) % list.size();
        return;
      }
      if (navRight) {
        currentImgIndex = (currentImgIndex + 1) % list.size();
        return;
      }
      if (navUp) {
        mode = MODE_PICK_CAT;
        return;
      }
      break;
    }

  case MODE_MOVE_OBJ:
    {
      if (objects.size() == 0 || selectedObjIndex < 0 || selectedObjIndex >= objects.size()) {
        mode = MODE_PICK_IMG;
        return;
      }
      DrawingObject obj = objects.get(selectedObjIndex);

      if (navLeft) {
        pushUndo();
        obj.x -= 10;
        return;
      }
      if (navRight) {
        pushUndo();
        obj.x += 10;
        return;
      }
      if (navUp) {
        pushUndo();
        obj.y -= 10;
        return;
      }
      if (navDown) {
        pushUndo();
        obj.y += 10;
        return;
      }

      if (rotKey && !Fn) {
        pushUndo();
        obj.angle += radians(5);
        return;
      }
      if (rotKey && Fn) {
        pushUndo();
        obj.angle -= radians(5);
        return;
      }
      if (scaleKey && Fn) {
        pushUndo();
        obj.size += 0.05;
        return;
      }
      if (scaleKey && !Fn) {
        pushUndo();
        obj.size = max(0.05, obj.size - 0.05);
        return;
      }

      if ("10P".equals(msg) && !Fn) {
        mode = MODE_SELECT_OBJ;
        selectedObjIndex = 0;
        println("Entering MODE_SELECT_OBJ");
        return;
      }

      break;
    }
  }
}

