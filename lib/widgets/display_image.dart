import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/*
 some of the code from:  
  https://blog.codemagic.io/text-recognition-using-firebase-ml-kit-flutter/
  https://github.com/flutter-ml/google_ml_kit_flutter/tree/develop/packages/example
*/

const String imageSrc = "assets/3.jpg";

// code to convert a jpeg to InputImage
Future<InputImage> inputImageFromJpegFile(File file) async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return inputImageFromJpegFileIOS(file); // iOS version
  } else {
    return inputImageFromJpegFileAndroid(file); // Your existing Android version
  }
}

Future<InputImage> inputImageFromJpegFileIOS(File file) async {
  final bytes = await file.readAsBytes();
  final image = img.decodeImage(bytes);
  if (image == null) {
    throw Exception('Unable to decode image');
  }
  // Convert image to BGRA8888 format
  final bgraData = _convertToBGRA8888(image);
  final inputImageData = InputImageMetadata(
    size: Size(image.width.toDouble(), image.height.toDouble()),
    rotation: InputImageRotation.rotation0deg, // Fixed rotation
    format: InputImageFormat.bgra8888, // Using BGRA8888 format for iOS
    bytesPerRow: image.width *
        4, // For BGRA8888, bytesPerRow is width * 4 (4 bytes per pixel)
  );
  return InputImage.fromBytes(
    bytes: bgraData,
    metadata: inputImageData,
  );
}

Uint8List _convertToBGRA8888(img.Image image) {
  final int width = image.width;
  final int height = image.height;
  final bgraBytes = Uint8List(width * height * 4);
  int pixelIndex = 0;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final pixel = image.getPixel(x, y);
      bgraBytes[pixelIndex++] = pixel.b.toInt(); // Blue
      bgraBytes[pixelIndex++] = pixel.g.toInt(); // Green
      bgraBytes[pixelIndex++] = pixel.r.toInt(); // Red
      bgraBytes[pixelIndex++] = pixel.a.toInt(); // Alpha
    }
  }
  return bgraBytes;
}

Future<InputImage> inputImageFromJpegFileAndroid(File file) async {
  final bytes = await file.readAsBytes();
  final image = img.decodeImage(bytes);

  if (image == null) {
    throw Exception('Unable to decode image');
  }

  // Convert image to NV21 format
  final nv21Data = _convertToNV21(image);

  final inputImageData = InputImageMetadata(
    size: Size(image.width.toDouble(), image.height.toDouble()),
    rotation: InputImageRotation.rotation0deg, // Fixed rotation
    format: InputImageFormat.nv21, // Using NV21 format
    bytesPerRow: image.width, // For NV21, bytesPerRow is equal to width
  );

  return InputImage.fromBytes(
    bytes: nv21Data,
    metadata: inputImageData,
  );
}

Uint8List _convertToNV21(img.Image image) {
  final int width = image.width;
  final int height = image.height;
  final int uvRowStride = width;
  final int uvPixelStride = 1;

  final yuvBytes = Uint8List(width * height * 3 ~/ 2);

  int yIndex = 0;
  int uvIndex = width * height;

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final pixel = image.getPixel(x, y);
      final int r = pixel.r.toInt();
      final int g = pixel.g.toInt();
      final int b = pixel.b.toInt();

      // YUV conversion
      int yValue = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
      yValue = yValue.clamp(0, 255);
      yuvBytes[yIndex++] = yValue;

      // UV conversion
      if (y % 2 == 0 && x % 2 == 0) {
        int uValue = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
        int vValue = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
        uValue = uValue.clamp(0, 255);
        vValue = vValue.clamp(0, 255);
        yuvBytes[uvIndex + (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride] =
            vValue;
        yuvBytes[uvIndex +
            (y ~/ 2) * uvRowStride +
            (x ~/ 2) * uvPixelStride +
            1] = uValue;
      }
    }
  }

  return yuvBytes;
}
//

class DisplayImage extends StatefulWidget {
  const DisplayImage({super.key});

  @override
  State<DisplayImage> createState() => _DisplayImageState();
}

class _DisplayImageState extends State<DisplayImage> {
  var script = TextRecognitionScript.latin;
  var textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  late File imageFile;
  Size? _imageSize;
  String? recognizedText;
  List<TextElement> _elements = [];

  Future<File> getImageFileFromAssets(String path) async {
    final byteData = await rootBundle.load(path);
    final buffer = byteData.buffer;
    Directory tempDir = await getTemporaryDirectory();
    String tempPath = tempDir.path;
    var filePath =
        tempPath + '/file_01.jpeg'; // file_01.tmp is dump file, can be anything
    return (File(filePath).writeAsBytes(
        buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes)));
  }

  void _initializeVision() async {
    imageFile = await getImageFileFromAssets(imageSrc);

    await _getImageSize(imageFile);
    InputImage inputImage = await inputImageFromJpegFile(imageFile);
    print(imageFile);
    print(inputImage.metadata!.rotation);
    print(inputImage.metadata!.size);
    final rt = await textRecognizer.processImage(inputImage);

    for (TextBlock block in rt.blocks) {
      for (TextLine line in block.lines) {
        for (TextElement element in line.elements) {
          _elements.add(element);
        }
      }
    }

    if (mounted) {
      setState(() {
        recognizedText = rt.text;
      });
    }
  }

  Future<void> _getImageSize(File imageFile) async {
    final Completer<Size> completer = Completer<Size>();

    final Image image = Image.file(imageFile);
    // Retrieving its size
    image.image.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((ImageInfo info, bool _) {
        completer.complete(Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        ));
      }),
    );

    final Size imageSize = await completer.future;
    setState(() {
      _imageSize = imageSize;
    });
  }

  @override
  void initState() {
    _initializeVision();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return recognizedText != null
        ? Stack(
            children: <Widget>[
              Center(
                child: Container(
                  width: double.maxFinite,
                  color: Colors.black,
                  child: CustomPaint(
                    foregroundPainter:
                        TextDetectorPainter(_imageSize!, _elements),
                    child: AspectRatio(
                      aspectRatio: _imageSize!.aspectRatio,
                      child: Image.file(
                        imageFile,
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Card(
                  elevation: 8,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            "Recognized Text",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 60,
                          child: SingleChildScrollView(
                            child: Text(
                              recognizedText!,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          )
        : Container(
            color: Colors.black,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
  }
}

class TextDetectorPainter extends CustomPainter {
  TextDetectorPainter(this.absoluteImageSize, this.elements);

  final Size absoluteImageSize;
  final List<TextElement> elements;

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / absoluteImageSize.width;
    final double scaleY = size.height / absoluteImageSize.height;

    Rect scaleRect(TextElement container) {
      return Rect.fromLTRB(
        container.boundingBox.left * scaleX,
        container.boundingBox.top * scaleY,
        container.boundingBox.right * scaleX,
        container.boundingBox.bottom * scaleY,
      );
    }

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.red
      ..strokeWidth = 2.0;

    for (TextElement element in elements) {
      canvas.drawRect(scaleRect(element), paint);
    }
  }

  @override
  bool shouldRepaint(TextDetectorPainter oldDelegate) {
    return true;
  }
}
