// Menu pop-up dimensions
float menuW = 400;
float menuH = 300;


float buttonW = 150;
float buttonH = 40;
float buttonSpacing = 20;
float menuX, menuY;

float btnStartY = menuY + menuH * 0.3;       // start ~30% down from top
float btnGap = buttonH + buttonSpacing;

float saveY  = btnStartY;
float loadY  = btnStartY + btnGap;
float closeY = btnStartY + 2 * btnGap;


void showSaveLoadMenu() {
  rectMode(CORNER);  // Make sure rect(x,y,w,h) is top-left corner
  menuX = (width - menuW) / 2;
  menuY = (height - menuH) / 2;
  
  // Semi-transparent background for pop-up
  fill(0, 180);
  noStroke();
  rect(0, 0, width, height);

  // Menu box with shadow
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

  // Buttons positions
  float bx = menuX + (menuW - buttonW) / 2;
  float saveY = menuY + 70;
  float loadY = saveY + buttonH + buttonSpacing;
  float closeY = loadY + buttonH + buttonSpacing;

  // Button hover check
  boolean hoverSave = mouseX > bx && mouseX < bx + buttonW && mouseY > saveY && mouseY < saveY + buttonH;
  boolean hoverLoad = mouseX > bx && mouseX < bx + buttonW && mouseY > loadY && mouseY < loadY + buttonH;
  boolean hoverClose = mouseX > bx && mouseX < bx + buttonW && mouseY > closeY && mouseY < closeY + buttonH;

  // Save button
  fill(hoverSave ? color(80, 180, 80) : color(100, 200, 100));
  rect(bx, saveY, buttonW, buttonH, 10);
  fill(0);
  textSize(18);
  textAlign(CENTER, CENTER);
  text("Save", bx + buttonW / 2, saveY + buttonH / 2);

  // Load button
  fill(hoverLoad ? color(80, 80, 180) : color(100, 100, 200));
  rect(bx, loadY, buttonW, buttonH, 10);
  fill(255);
  text("Load", bx + buttonW / 2, loadY + buttonH / 2);

  // Close button
  fill(hoverClose ? color(180, 80, 80) : color(200, 100, 100));
  rect(bx, closeY, buttonW, buttonH, 10);
  fill(0);
  text("Close", bx + buttonW / 2, closeY + buttonH / 2);

  // Input box for filename if typing
if (typingFilename) {
    float inputX = menuX + 25;
    float inputY = btnStartY + 3 * btnGap + 10;  // a little gap below last button
    float inputW = menuW - 50;
    float inputH = 35;

    fill(255);
    stroke(150);
    strokeWeight(1.5);
    rect(inputX, inputY, inputW, inputH, 8);
    noStroke();

    fill(0);
    textAlign(LEFT, CENTER);
    textSize(16);
    text(inputFilename + "|", inputX + 8, inputY + inputH / 2); // cursor
}

}


void handleMenuClick() {
  float bx = menuX + (menuW - buttonW) / 2;
  float saveY = menuY + 70;
  float loadY = saveY + buttonH + buttonSpacing;
  float closeY = loadY + buttonH + buttonSpacing;

  // Save
  if (mouseX > bx && mouseX < bx + buttonW && mouseY > saveY && mouseY < saveY + buttonH) {
    saveObjectsCSV("drawing.csv");
    showMenu = false;
    typingFilename = false;
    return;
  }

  // Load
  if (mouseX > bx && mouseX < bx + buttonW && mouseY > loadY && mouseY < loadY + buttonH) {
    inputFilename = "";
    typingFilename = true;
    return;
  }

  // Close
  if (mouseX > bx && mouseX < bx + buttonW && mouseY > closeY && mouseY < closeY + buttonH) {
    showMenu = false;
    typingFilename = false;
    return;
  }
}

void handleMenuKey(char k) {
  if (!showMenu || !typingFilename) return;

  if (k == BACKSPACE) {
    if (inputFilename.length() > 0) inputFilename = inputFilename.substring(0, inputFilename.length() - 1);
  } else if (k == ENTER || k == RETURN) {
    loadObjectsFromInput(inputFilename);
    typingFilename = false;
    showMenu = false;
  } else if (k != CODED) {
    inputFilename += k;
  }
}
