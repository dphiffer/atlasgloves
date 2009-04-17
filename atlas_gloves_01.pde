/**
 * Atlas Gloves (http://atlasgloves.org/)
 * Release 01 / May 2006
 * A DIY Hand Gesture Interface for Google Earth
 * By Dan Phiffer (dan@phiffer.org) and Mushon Zer-Aviv (mushon@shual.com)
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the FreeSoftware
 * Foundation; either version 2 of the License, or (at your option) any later
 * version.
 *
 * This program is distributed in the hope that it will be useful, but
WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along
with
 * this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

// The robot library gives us virtual hands (click / drag simulation)
import java.awt.Robot;

// The video library gives us virtual eyes (motion tracking)
import processing.video.*;

// The three main actors
Robot robot;
Capture video;
Target target;

// An instructional demo animation
Movie demo;

// Assigning proportions
int videoW = 102;
int videoH = 77;
int screenW = 1024;
int screenH = 768;
int scl = 4; //scaling the screen and the input
int frame_rate = 24;

// Brightness threshold for blob inclusion
// (Press + / - keys to adjust these at runtime)
float threshold = 200.0;

// These boolean variables control which mouse events will be simulated
// (Press m / c to control each of these, respectively)
boolean simulateMove = false;
boolean simulateClick = false;

// Mode thresholds, based on blob width and height
int panW = 4;
int panH = 4;
int zoomH = 8;
int tiltW = 12;
int menuH = 30;

// Zoom thresholds
int zoomInMax = 10;
int zoomOutMin = 30;

boolean mouse1 = false;  // Left mouse button status
boolean mouse2 = false;  // Middle mouse button status

int angle;               // The angle of the line connecting the lights
int oldAngle = 0;        // Used to calculate the change in angle
int oldHeight = 0;       // Used to calculate the change in blob height
int panBuffer = 0;

// These variables determine which corners of the blob comprise the line
boolean firstIncluded = true;
int firstCol = 0;
int firstRow = 0;

// Keeps track of interaction modes
int mode = -1; /*
                * -1 = waiting
                * 0  = zoom
                * 1  = tilt
                * 2  = pan
                * 3  = rotate
                */

// Mode images:
PImage demo_mode;
PImage practice_mode;
PImage control_mode;

int playMode = 1;                  // Start out in demo mode
int resetCount = frame_rate * 15;  // Reset after 15 sec
int resetTimer = -1;
int demoAlpha = 200;

void setup() {

  // The robot needs a try/catch block to be initiated
  try {
    robot = new Robot();
    //press_alt_tab();
  } catch (Exception e) {
    println("Oops, something went wrong.");
  }

  // Basic processing setup
  framerate(frame_rate);
  size(scl * videoW, scl * videoH);
  background(0);
  stroke(51, 255, 102);
  strokeWeight(3);

  // Initiate the video, resolution and frame rate
  video = new Capture(this, videoW, videoH, frame_rate);

  // Make our target object
  target = new Target();

  // Load and play the demo movie file
  demo = new Movie(this, "demo.mov");
  demo.play();

  // Load the images
  demo_mode = loadImage ("demo_mode.gif");
  practice_mode = loadImage ("practice_mode.gif");
  control_mode = loadImage ("control_mode.gif");
}

void draw() {
  if (playMode == 0) {
    if (demo.available()) {
      demo.read();
    }
    capture();
    smooth();
    tint(255, 255, 255, demoAlpha);
    image(demo, -60, -15);
    if (demo.duration() == demo.time()) {
      demoAlpha -= 10;
      if (demoAlpha < 50) {
        playMode = 1;
      }
    }
  } else {
    noTint();
    capture();
    smooth();
  }

  switch(playMode) {
    case 0:
      image(demo_mode, 5, 5); break;
    case 1:
      image(practice_mode, 5, 5); break;
    case 2:
      image(control_mode, 5, 5); break;
  }

}

void capture() {

  firstIncluded = true;

  // Iterate over each pixel in the video frame to find a light blob
  for (int row = 0; row < video.height; row++) { // For each row
    for(int col = 0; col < video.width; col++) { // For each column

      color pixel = video.pixels[row * video.width + col];

      // If the pixel is bright enough, include it in the blob
      if (target.isSimilar(pixel)){
        target.include(col, row);

        // The first time we include a light determines the angle
        //   of the line we draw within the blob
        if (firstIncluded) {
          firstIncluded = false;
          firstCol = col;
          firstRow = row;
        }
      }
    }
  }

  // Flip the video image to make it mirror-like
  pushMatrix();
  scale(-1, 1);
  image(video, -width, 0, videoW * scl, videoH * scl);
  target.drawIt();
  popMatrix();  //pops out to work with different proportions
}

// Video tracking algorithm based on code from Dan O'Sullivan
// http://itp.nyu.edu/~dbo3/cgi-bin/ClassWiki.cgi?ICMVideo

class Target {

  Rectangle blob;

  void include(int _x, int _y) {
    if (blob == null) {
      blob = new Rectangle(_x,_y,1,1);
    }
    blob.add(_x,_y);
  }

  boolean isSimilar(color thisPixel) {
    if (brightness(thisPixel) > threshold){
      return true;
    }
    return false;
  }

  void drawIt() {

    if (blob != null) {

      resetTimer = -1;

      // Draw a line to the video capture
      this.drawLine();

      // Switch to practice mode
      if (playMode == 0 && blob.width > panW &&
          blob.y + blob.height > videoH * 0.9) {
        playMode = 1;
        demoAlpha = 0;
      }

      // Switch to control mode from demo or practice
      // (hands held high)
      if (playMode < 2 && blob.width > panW &&
          blob.y + blob.height < videoH * 0.1) {
        playMode = 2;
        press_alt_tab();
        simulateClick = true;
        simulateMove = true;
      }

      // Switch from control mode to demo mode
      // (hands held low)
      if (playMode == 2 && blob.width > panW &&
          blob.y + blob.height > videoH * 0.9) {
        resetTimer = resetCount + 1;
      }

      if (simulateMove &&
          mouse1 &&
          mode == 2 &&
          blob.width <= panW &&
          blob.height <= panH) {
        // If we're already panning, move the mouse around
        this.move();
      }

      if (simulateClick) {
        switch(mode) {
          case -1:
            this.chooseMode(); break;
          case 0:
            this.zoom(); break;
          case 1:
            this.tilt(); break;
          case 2:
            this.pan(); break;
          case 3:
            this.rotate(); break;
        }
      }

    } else if (panBuffer < 3) {
      panBuffer++;
    } else {
      panBuffer = 0;
      mode = -1;
      if (mouse1) {
        robot.mouseRelease(InputEvent.BUTTON1_MASK);
        mouse1 = false;
      }
      if (mouse2) {
        robot.mouseRelease(InputEvent.BUTTON2_MASK);
        mouse2 = false;
      }
    }
    blob = null; //collapse the box again

    if (resetTimer == -1) {
      resetTimer = 0;
    } else if (resetTimer > resetCount) {
      press_alt_tab();
      simulateClick = false;
      simulateMove = false;
      playMode = 0;
      resetTimer = -1;
      demo.jump(0.0);
      demo.play();
      demoAlpha = 200;
    }
    if (playMode == 2) {
      resetTimer++;
    }

  }

  void drawLine() {

    int x1 = scl * blob.x;
    int y1 = scl * blob.y;
    int x2 = scl * (blob.x + blob.width);
    int y2 = scl * (blob.y + blob.height);

    if (abs(x1 - scl * firstCol) < 5 && abs(y1 - scl * firstRow) < 5) {
      line(x1 - width, y1, x2 - width, y2);
      angle = (int) degrees(atan2 (y2-y1,(x2-width)-(x1-width)));
    } else {
      line(x1 - width, y2, x2 - width, y1);
      angle = (int) degrees(atan2 (y1-y2, (x2-width)-(x1-width)));
    }
  }

  void chooseMode() {
    if (!mouse2 && blob.width >= panW && blob.height < zoomH) {
      mode = 0;
      println("Entering zoom mode.");
      this.zoom();
    } else if (blob.height >= panH && blob.width < tiltW) {
      mode = 1;
      println("Entering tilt mode.");
      this.tilt();
    } else if (blob.width < panW && blob.height < panH) {
      mode = 2;
      println("Entering pan mode.");
      this.pan();
    } else {
      mode = 3;
      println("Entering rotate mode.");
      this.rotate();
    }
  }

  void move() {
    int x = screenW - (2 * blob.x + blob.width) / 2 * screenW / videoW;
    int y = (2 * blob.y + blob.height) / 2  * screenH / videoH;
    if (y < menuH) {
      y = menuH;
    }
    robot.mouseMove(x, y);
  }

  void pan() {
    if (blob.width > tiltW || blob.height > zoomH) {
      if (mouse1) {
        robot.mouseRelease(InputEvent.BUTTON1_MASK);
      }
      this.chooseMode();
    } else {
      if (mouse2) {
        robot.mouseRelease(InputEvent.BUTTON2_MASK);
        mouse2 = false;
      } else if (mouse1) {
        return;
      } else if (panBuffer < 3) {
        panBuffer++;
      } else {
        panBuffer = 0;
        this.move();
        robot.mousePress(InputEvent.BUTTON1_MASK);
        mouse1 = true;
      }
    }
  }

  void zoom() {
    panBuffer = 0;
    if (blob.width < panW && blob.height < panH) {
      return;
    }
    if (blob.width < zoomInMax ) {
      robot.mouseWheel(1);
    } else if (blob.width > zoomOutMin) {
      robot.mouseWheel(-1);
    }
  }

  void rotate() {
    panBuffer = 0;
    if (blob.width < panW && blob.height < panH) {
      return;
    }
    if (!mouse2) {
      robot.mouseMove(screenW / 2, screenH / 2);
      robot.mousePress(InputEvent.BUTTON2_MASK);
      oldAngle = angle;
      mouse2 = true;
    } else {
      int angleDiff = (oldAngle - angle) * 10;
      robot.mouseMove(screenW / 2 + angleDiff, screenH / 2);
    }
  }

  void tilt() {
    panBuffer = 0;
    if (blob.width < panW && blob.height < panH) {
      return;
    }
    if (!mouse2) {
      robot.mouseMove(screenW / 2, screenH / 2);
      robot.mousePress(InputEvent.BUTTON2_MASK);
      oldHeight = blob.height;
      mouse2 = true;
    } else {
      int heightDiff = (oldHeight - blob.height);
      robot.mouseMove(screenW / 2, screenH / 2 + heightDiff * 10);
    }
  }
}

// Handle incoming video data
void captureEvent(Capture camera) {
  camera.read();
}

void keyPressed() {
  // Down arrow
  if (keyCode == 38){
    threshold++;
    println("Threshold: " + threshold);
  } else if (keyCode == 40) {
    threshold--;
    println("Threshold: " + threshold);
  } else if (keyCode == 67) {
    simulateClick = !simulateClick;
    if (simulateClick) {
      println("Click: on");
    } else {
      println("Click: off");
    }
  } else if (keyCode == 77) {
    simulateMove = !simulateMove;
    if (simulateMove) {
      println("Move: on");
    } else {
      println("Move: off");
    }
  }
}

void press_alt_tab() {
    robot.keyPress(18);
    robot.keyPress(9);
    robot.keyRelease(9);
    robot.keyRelease(18);
}
