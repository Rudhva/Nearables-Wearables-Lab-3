// --- Menu layout setup ---
float menuW = 450;
float menuH = 320;
float buttonW = 150;
float buttonH = 40;
float buttonSpacing = 20;
float menuX, menuY;

// --- Menu state variables ---
boolean showMenu = false;
boolean typingFilename = false;
boolean typingForSave = false;
String inputFilename = "";

// --- Button navigation ---
int selectedMenuButton = 0; // 0 = Save, 1 = Load, 2 = Close
String[] menuButtons = {"Save", "Load", "Close"};

// --- Virtual keyboard setup ---
String[][] keyboardRows = {
  {"q","w","e","r","t","y","u","i","o","p"},
  {"a","s","d","f","g","h","j","k","l"},
  {"z","x","c","v","b","n","m"},
  {"space",".","backspace","enter","back"}
};

float keyW = 40;
float keyH = 40;
float keySpacing = 8;
float keyboardY;
int selectedRow = 0;
int selectedCol = 0;

// ===========================================================
// MENU DISPLAY
// ===========================================================

void showSaveLoadMenu() {
  rectMode(CORNER);
  menuX = (width - menuW) / 2;
  menuY = (height - menuH) / 2;

  // Dim background
  fill(0, 180);
  noStroke();
  rect(0, 0, width, height);

  // Main box
  fill(240);
  stroke(50, 50, 50, 100);
  strokeWeight(3);
  rect(menuX, menuY, menuW, menuH, 15);
  noStroke();

  // Title
  fill(30);
  textSize(22);
  textAlign(CENTER, CENTER);
  text("Save / Load Menu", menuX + menuW / 2, menuY + 30);

  // --- Buttons (Save, Load, Close) ---
  float bx = menuX + (menuW - buttonW) / 2;
  float saveY = menuY + 70;
  float loadY = saveY + buttonH + buttonSpacing;
  float closeY = loadY + buttonH + buttonSpacing;

  for (int i = 0; i < menuButtons.length; i++) {
    float by = saveY + i * (buttonH + buttonSpacing);

    // Highlight selected button
    if (!typingFilename && i == selectedMenuButton) {
      stroke(255, 255, 0);
      strokeWeight(3);
    } else {
      noStroke();
    }

    // Button color
    if (i == 0) fill(100, 200, 100);      // Save
    else if (i == 1) fill(100, 100, 200); // Load
    else fill(200, 100, 100);             // Close

    rect(bx, by, buttonW, buttonH, 10);
    fill(0);
    textAlign(CENTER, CENTER);
    text(menuButtons[i], bx + buttonW / 2, by + buttonH / 2);
  }
  noStroke();

  // --- Filename input & virtual keyboard ---
  if (typingFilename) {
    float inputX = menuX + 25;
    float inputY = closeY + 85;
    float inputW = menuW - 50;
    float inputH = 35;

    fill(0);
    textAlign(CENTER, BOTTOM);
    textSize(16);
    text(typingForSave ? "Enter filename to SAVE:" : "Enter filename to LOAD:", menuX + menuW / 2, inputY - 15);

    fill(255);
    stroke(150);
    strokeWeight(1.5);
    rect(inputX, inputY, inputW, inputH, 8);
    noStroke();

    fill(0);
    textAlign(LEFT, CENTER);
    text(inputFilename + "|", inputX + 8, inputY + inputH / 2);

    drawVirtualKeyboard(inputY + 50);
  }
}

// ===========================================================
// VIRTUAL KEYBOARD DISPLAY
// ===========================================================

void drawVirtualKeyboard(float startY) {
  keyboardY = startY;
  textSize(16);
  textAlign(CENTER, CENTER);

  for (int r = 0; r < keyboardRows.length; r++) {
    String[] row = keyboardRows[r];
    float rowWidth = 0;
    for (String key : row) {
      float w = key.equals("space") ? keyW * 3 :
                key.equals("backspace") ? keyW * 2 :
                key.equals("enter") ? keyW * 2 :
                key.equals("back") ? keyW * 2 : keyW;
      rowWidth += w + keySpacing;
    }
    float rowX = menuX + (menuW - rowWidth + keySpacing) / 2;
    float y = startY + r * (keyH + keySpacing);

    float x = rowX;
    for (int c = 0; c < row.length; c++) {
      String key = row[c];
      float w = key.equals("space") ? keyW * 3 :
                key.equals("backspace") ? keyW * 2 :
                key.equals("enter") ? keyW * 2 :
                key.equals("back") ? keyW * 2 : keyW;

      // Highlight current selection
      if (r == selectedRow && c == selectedCol) {
        fill(80, 160, 255);
      } else {
        // Color code the back button differently
        if (key.equals("back")) {
          fill(255, 200, 100);
        } else {
          fill(220);
        }
      }
      stroke(100);
      rect(x, y, w, keyH, 6);
      fill(0);
      text(key, x + w / 2, y + keyH / 2);
      x += w + keySpacing;
    }
  }
}

// ===========================================================
// MENU KEY HANDLER
// ===========================================================

void handleMenuKey(String serialMsg) {
  if (!showMenu) return;

  // --- MENU BUTTON SELECTION MODE ---
  if (!typingFilename) {
    if ("1P".equals(serialMsg)) { // Up
      selectedMenuButton--;
      if (selectedMenuButton < 0) selectedMenuButton = menuButtons.length - 1;
    } else if ("3P".equals(serialMsg)) { // Down
      selectedMenuButton++;
      if (selectedMenuButton >= menuButtons.length) selectedMenuButton = 0;
    } else if ("5P".equals(serialMsg)) { // OK/Enter
      // "Click" selected button
      if (selectedMenuButton == 0) { // Save
        inputFilename = "";
        typingFilename = true;
        typingForSave = true;
        selectedRow = 0;
        selectedCol = 0;
      } else if (selectedMenuButton == 1) { // Load
        inputFilename = "";
        typingFilename = true;
        typingForSave = false;
        selectedRow = 0;
        selectedCol = 0;
      } else if (selectedMenuButton == 2) { // Close
        showMenu = false;
      }
    }
    return;
  }

  // --- FILENAME TYPING MODE ---
  if ("4P".equals(serialMsg)) { // Left
    selectedCol--;
    if (selectedCol < 0) selectedCol = keyboardRows[selectedRow].length - 1;
  } else if ("2P".equals(serialMsg)) { // Right
    selectedCol++;
    if (selectedCol >= keyboardRows[selectedRow].length) selectedCol = 0;
  } else if ("1P".equals(serialMsg)) { // Up
    selectedRow--;
    if (selectedRow < 0) selectedRow = keyboardRows.length - 1;
    selectedCol = min(selectedCol, keyboardRows[selectedRow].length - 1);
  } else if ("3P".equals(serialMsg)) { // Down
    selectedRow++;
    if (selectedRow >= keyboardRows.length) selectedRow = 0;
    selectedCol = min(selectedCol, keyboardRows[selectedRow].length - 1);
  } else if ("5P".equals(serialMsg)) { // OK/Enter
    pressSelectedKey();
  }
}

// ===========================================================
// KEYBOARD PRESS ACTIONS
// ===========================================================

void pressSelectedKey() {
  String key = keyboardRows[selectedRow][selectedCol];

  if (key.equals("space")) {
    inputFilename += " ";
  } else if (key.equals("backspace")) {
    if (inputFilename.length() > 0)
      inputFilename = inputFilename.substring(0, inputFilename.length() - 1);
  } else if (key.equals("enter")) {
    if (typingForSave) {
      saveObjectsCSV(inputFilename + ".csv");
    } else {
      loadObjectsFromInput(inputFilename);
    }
    typingFilename = false;
    showMenu = false;
    typingForSave = false;
    inputFilename = "";
  } else if (key.equals("back")) {
    // Go back to main menu
    typingFilename = false;
    typingForSave = false;
    inputFilename = "";
  } else {
    inputFilename += key;
  }
}

// ===========================================================
// MOUSE HANDLER
// ===========================================================

void mousePressed() {
  if (showMenu) {
    // Optionally handle clicks later if needed
    return;
  }
}
