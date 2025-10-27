// -------------------------
// serial.pde (Processing)
// -------------------------
import processing.serial.*;


final int SERIAL_PORT_INDEX = 7; 

Serial myPort;
String latestSerialMessage = "";
boolean Fn  = false;
boolean tap = false;

// Call this ONCE from setup() in your main .pde:
//   setupSerial();
void setupSerial() {
  println("Serial ports:");
  String[] ports = Serial.list();
  for (int i = 0; i < ports.length; i++) println("  ["+i+"] "+ports[i]);
  if (ports.length == 0) { println("No serial ports found."); return; }

  String chosen;
  if (SERIAL_PORT_INDEX >= 0 && SERIAL_PORT_INDEX < ports.length) {
    chosen = ports[SERIAL_PORT_INDEX];               // <<< force by index
  } else {
    // better auto-pick: prefer usbmodem/usbserial/tty.*
    chosen = ports[ports.length - 1];
    for (String p : ports) {
      String pl = p.toLowerCase();
      if ((pl.contains("usbmodem") || pl.contains("usbserial") || pl.contains("tty."))
          && !pl.contains("bluetooth")) { chosen = p; break; }
    }
  }

  try {
    myPort = new Serial(this, chosen, 115200);
    myPort.clear();
    myPort.bufferUntil('\n');
    println("Opened serial on " + chosen + " @115200");
  } catch (Exception e) {
    println("Failed to open serial: " + e.getMessage());
  }
}


String readSerialMessage() { return latestSerialMessage; }

void serialEvent(Serial p) {
  String input = p.readStringUntil('\n');
  if (input == null) { tap = false; return; }

  tap = true;
  input = input.trim();

  // Normalize: "10 Pressed"→"10P", "6 Released"→"6R", "F" stays "F"
  String msg = input;
  if (msg.matches("^\\d+\\s*[PpRr].*$")) {
    msg = msg.replaceAll("^(\\d+)\\s*([PpRr]).*$", "$1$2").toUpperCase();
  } else if (msg.matches("^\\d+.*$")) {
    msg = msg.replaceAll("^(\\d+).*$", "$1P").toUpperCase();
  } else {
    msg = msg.trim().toUpperCase();
  }

  latestSerialMessage = msg;
  println("SERIAL: " + latestSerialMessage);

  processSerialMessage(latestSerialMessage);
  latestSerialMessage = "";
}

// Highlight pads on the hand UI when serial is used
void highlightForSerial(String msg) {
  if ("1P".equals(msg))      markPressed("UP");
  else if ("2P".equals(msg)) markPressed("RIGHT");
  else if ("3P".equals(msg)) markPressed("DOWN");
  else if ("4P".equals(msg)) markPressed("LEFT");
  else if ("5P".equals(msg)) markPressed("OK");
  else if ("6P".equals(msg)) markPressed("FN");
  else if ("7P".equals(msg)) markPressed(Fn ? "I" : "K"); // scale: Fn=bigger (I), no-Fn=smaller (K)
  else if ("8P".equals(msg)) markPressed(Fn ? "J" : "L"); // rotate: Fn=CCW (J), no-Fn=CW (L)
}


void processSerialMessage(String msg) {
  if (msg == null || msg.length() == 0) return;
  highlightForSerial(msg);

  // If SAVE/LOAD MENU is open, route pad arrows/OK to it (works with "1P..5P")
  if (showMenu) { handleMenuKey(msg); return; }

  boolean okKey = false;

  // Flex
  // --- Flex sensor F → OPEN MENU ---
  if ("F".equals(msg)) {
    showMenu = true;
    typingFilename = false;
    menuX = (width - menuW) / 2;
    menuY = (height - menuH) / 2;
    println("Menu opened by FLEX");
    return; // important: prevent falling through to other modes
  }


  // Fn latch
  if ("6P".equals(msg)) { Fn = true;  return; }
  if ("6R".equals(msg)) { Fn = false; return; }

  // Undo / Redo
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

  // Select mode / open menu (10P)
  if ("10P".equals(msg) && !Fn) {
    mode = MODE_SELECT_OBJ; selectedObjIndex = 0;
    println("Entering MODE_SELECT_OBJ");
    return;
  }
  if ("10P".equals(msg) && Fn) {
    showMenu = true; typingFilename = false;
    menuX = (width - menuW) / 2; menuY = (height - menuH) / 2;
    println("Opened Save/Load Menu");
    return;
  }

  // OK (5P)
  if ("5P".equals(msg)) {
    okKey = true;
    switch (mode) {
      case MODE_PICK_BG:
        if (bgFilenames.size() > 0) { setBackgroundFromPath(bgFilenames.get(currentBgIndex)); mode = MODE_PICK_CAT; }
        return;
      case MODE_PICK_CAT:
        currentImgIndex = 0; mode = MODE_PICK_IMG; return;
      case MODE_PICK_IMG: {
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
        if (Fn) deleteSelectedTrack(); else mode = MODE_PICK_IMG;
        return;
      case MODE_SELECT_OBJ:
        mode = MODE_MOVE_OBJ; return;
    }
  }

  // Pad arrows
  boolean navUp    = "1P".equals(msg);
  boolean navRight = "2P".equals(msg);
  boolean navDown  = "3P".equals(msg);
  boolean navLeft  = "4P".equals(msg);

  // Scale / Rotate
  boolean scaleKey = "7P".equals(msg);
  boolean rotKey   = "8P".equals(msg);

  switch (mode) {
    case MODE_SELECT_OBJ:
      if (objects.size() == 0) return;
      if (navUp)   { selectedObjIndex = (selectedObjIndex + 1) % objects.size(); return; }
      if (navDown) { selectedObjIndex = (selectedObjIndex - 1 + objects.size()) % objects.size(); return; }
      if (okKey)   { mode = MODE_MOVE_OBJ; return; }
      break;

    case MODE_PICK_BG:
      if (bgFilenames.size() == 0) return;
      if (navLeft)  { currentBgIndex = (currentBgIndex - 1 + bgFilenames.size()) % bgFilenames.size(); return; }
      if (navRight) { currentBgIndex = (currentBgIndex + 1) % bgFilenames.size(); return; }
      break;

    case MODE_PICK_CAT:
      if (navLeft)  { currentCatIndex = (currentCatIndex - 1 + CATALOGS.length) % CATALOGS.length; return; }
      if (navRight) { currentCatIndex = (currentCatIndex + 1) % CATALOGS.length; return; }
      break;

    case MODE_PICK_IMG: {
      String cat = CATALOGS[currentCatIndex];
      ArrayList<String> list = catFiles.get(cat);
      if (list == null || list.size() == 0) return;
      if (navLeft)  { currentImgIndex = (currentImgIndex - 1 + list.size()) % list.size(); return; }
      if (navRight) { currentImgIndex = (currentImgIndex + 1) % list.size(); return; }
      if (navUp)    { mode = MODE_PICK_CAT; return; }
      break;
    }

    case MODE_MOVE_OBJ:
      if (objects.size() == 0 || selectedObjIndex < 0 || selectedObjIndex >= objects.size()) { mode = MODE_PICK_IMG; return; }
      DrawingObject obj = objects.get(selectedObjIndex);

      if (navLeft)  { pushUndo(); obj.x -= 10; return; }
      if (navRight) { pushUndo(); obj.x += 10; return; }
      if (navUp)    { pushUndo(); obj.y -= 10; return; }
      if (navDown)  { pushUndo(); obj.y += 10; return; }

      if (rotKey   && !Fn) { pushUndo(); obj.angle += radians(5); return; }
      if (rotKey   &&  Fn) { pushUndo(); obj.angle -= radians(5); return; }
      if (scaleKey &&  Fn) { pushUndo(); obj.size  += 0.05;       return; }
      if (scaleKey && !Fn) { pushUndo(); obj.size  = max(0.05, obj.size - 0.05); return; }

      if ("10P".equals(msg) && !Fn) {
        mode = MODE_SELECT_OBJ; selectedObjIndex = 0;
        println("Entering MODE_SELECT_OBJ");
        return;
      }
      break;
  }
}
