import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:image_picker/image_picker.dart';

import 'api_service.dart';

class OwnerParkingScreen extends StatefulWidget {
  const OwnerParkingScreen({Key? key}) : super(key: key);

  @override
  State<OwnerParkingScreen> createState() => _OwnerParkingScreenState();
}

class _OwnerParkingScreenState extends State<OwnerParkingScreen> {
  bool _isLoading = true;
  List<dynamic> _parkings = [];
  String? _ownerId;
  String _userEmail = '';

  static const String _googleMapsKey = 'AIzaSyBLcNB8R6m1PigssleaaOIsKEJG9zsYtxQ';

  final List<Map<String, dynamic>> _amenitiesList = [
    {'key': 'cctv', 'label': 'CCTV', 'icon': Icons.videocam, 'color': Colors.grey.shade600},
    {'key': 'security', 'label': 'Security', 'icon': Icons.security, 'color': Colors.blue.shade700},
    {'key': 'charging', 'label': 'Charging', 'icon': Icons.ev_station, 'color': Colors.purple.shade700},
    {'key': 'washroom', 'label': 'Washroom', 'icon': Icons.wc, 'color': Colors.blue},
    {'key': '24h', 'label': '24/7', 'icon': Icons.access_time, 'color': Colors.black54},
    {'key': 'shade', 'label': 'Shade', 'icon': Icons.park, 'color': Colors.green.shade700},
    {'key': 'valet', 'label': 'Valet', 'icon': Icons.car_rental, 'color': Colors.red.shade700},
    {'key': 'car_wash', 'label': 'Car Wash', 'icon': Icons.local_car_wash, 'color': Colors.pink.shade700},
  ];

  @override
  void initState() {
    super.initState();
    _fetchParkings();
  }

  /// Convert relative URL from API (e.g. "uploads/xyz.jpg") to full URL
  String _resolveImageUrl(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    // Strip leading slash if present
    final clean = raw.startsWith('/') ? raw.substring(1) : raw;
    return 'https://parkfro.com/API.php/$clean';
  }

  Future<void> _fetchParkings() async {
    setState(() => _isLoading = true);
    try {
      final session = await ApiService.getUserSession();
      _userEmail = session['email']?.toString() ?? '';

      final ownerRes = await http.get(
        Uri.parse('https://parkfro.com/API.php?table=parking_space_owners'),
      );
      if (ownerRes.statusCode == 200) {
        final ownerData = json.decode(ownerRes.body);
        if (ownerData['status'] == true && ownerData['data'] != null) {
          for (var owner in ownerData['data']) {
            if (owner['email']?.toString().toLowerCase() == _userEmail.toLowerCase() ||
                owner['user_id']?.toString() == session['userId']) {
              _ownerId = owner['id'].toString();
              break;
            }
          }
        }
      }

      if (_ownerId != null) {
        final parkingRes = await http.get(
          Uri.parse('https://parkfro.com/API.php?table=parking_spaces'),
        );
        if (parkingRes.statusCode == 200) {
          final parkingData = json.decode(parkingRes.body);
          if (parkingData['status'] == true && parkingData['data'] != null) {
            final allSpaces = parkingData['data'] as List;
            setState(() {
              _parkings = allSpaces
                  .where((p) => p['owner_id'].toString() == _ownerId)
                  .toList();
            });
          }
        }
      }
    } catch (e) {
      _showSnackBar('Error loading parkings.', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showParkingDialog({Map<String, dynamic>? parking}) {
    final bool isEditing = parking != null;

    final nameCtrl = TextEditingController(text: parking?['name'] ?? '');
    final addressCtrl = TextEditingController(text: parking?['address'] ?? '');
    final cityCtrl = TextEditingController(text: parking?['city'] ?? '');
    final latCtrl = TextEditingController(text: parking?['latitude'] ?? '');
    final lngCtrl = TextEditingController(text: parking?['longitude'] ?? '');
    final mapsUrlCtrl = TextEditingController(text: parking?['google_maps_url'] ?? '');
    final carCtrl = TextEditingController(text: parking?['car_capacity']?.toString() ?? '0');
    final bikeCtrl = TextEditingController(text: parking?['bike_capacity']?.toString() ?? '0');
    final suvCtrl = TextEditingController(text: parking?['suv_capacity']?.toString() ?? '0');
    final evCtrl = TextEditingController(text: parking?['ev_capacity']?.toString() ?? '0');

    String type = parking?['type']?.toString().toLowerCase() ?? 'Select Type';
    final typeOptions = ['Select Type', 'open', 'covered', 'basement', 'private', 'commercial'];
    if (!typeOptions.contains(type)) type = 'Select Type';

    String openTime = parking?['open_time'] ?? '--:-- --';
    String closeTime = parking?['close_time'] ?? '--:-- --';

    // ✅ FIX: Properly resolve existing photo URLs
    String? existingEntryPhotoUrl = _resolveImageUrl(parking?['entry_photo']?.toString());
    String? existingExitPhotoUrl = _resolveImageUrl(parking?['exit_photo']?.toString());
    if (existingEntryPhotoUrl.isEmpty) existingEntryPhotoUrl = null;
    if (existingExitPhotoUrl.isEmpty) existingExitPhotoUrl = null;

    List<String> existingAreaPhotos = [];
    if (parking != null && parking['area_photos'] != null) {
      try {
        final parsed = json.decode(parking['area_photos'].toString());
        if (parsed is List) {
          existingAreaPhotos = parsed
              .map((e) => _resolveImageUrl(e.toString()))
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }

    File? newEntryPhoto;
    File? newExitPhoto;
    List<File> newAreaPhotos = [];

    List<String> selectedAmenities = [];
    if (parking != null && parking['amenities'] != null) {
      try {
        final parsed = json.decode(parking['amenities'].toString());
        if (parsed is List) {
          selectedAmenities = parsed.map((e) => e.toString()).toList();
        }
      } catch (e) {
        debugPrint('Amenities parse error: $e');
      }
    }

    bool isSaving = false;
    bool isFetchingLocation = false;

    // Autocomplete state
    List<Map<String, dynamic>> addressSuggestions = [];
    Timer? debounce;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final isMobile = MediaQuery.of(dialogCtx).size.width < 600;

        return StatefulBuilder(
          builder: (context, setDialogState) {

            // ==================================================
            // GOOGLE PLACES AUTOCOMPLETE
            // ==================================================
            Future<void> fetchAddressSuggestions(String query) async {
              if (query.trim().length < 3) {
                setDialogState(() => addressSuggestions = []);
                return;
              }
              try {
                final url = Uri.parse(
                  'https://maps.googleapis.com/maps/api/place/autocomplete/json'
                      '?input=${Uri.encodeComponent(query)}'
                      '&key=$_googleMapsKey'
                      '&components=country:in',
                );
                final res = await http.get(url);
                if (res.statusCode == 200) {
                  final data = json.decode(res.body);
                  if (data['status'] == 'OK') {
                    setDialogState(() {
                      addressSuggestions = List<Map<String, dynamic>>.from(data['predictions']);
                    });
                  } else {
                    debugPrint('Places API status: ${data['status']} - ${data['error_message'] ?? ''}');
                  }
                }
              } catch (e) {
                debugPrint('Autocomplete error: $e');
              }
            }

            // ==================================================
            // GET LAT/LNG FROM PLACE ID
            // ==================================================
            Future<void> applyPlace(String placeId, String description) async {
              setDialogState(() {
                addressSuggestions = [];
                isFetchingLocation = true;
              });
              try {
                final url = Uri.parse(
                  'https://maps.googleapis.com/maps/api/place/details/json'
                      '?place_id=$placeId'
                      '&key=$_googleMapsKey'
                      '&fields=geometry,formatted_address,address_components',
                );
                final res = await http.get(url);
                if (res.statusCode == 200) {
                  final data = json.decode(res.body);
                  if (data['status'] == 'OK') {
                    final result = data['result'];
                    final loc = result['geometry']['location'];
                    final lat = loc['lat'];
                    final lng = loc['lng'];

                    // Extract city from components
                    String city = '';
                    for (var comp in result['address_components']) {
                      if (comp['types'].contains('locality')) {
                        city = comp['long_name'];
                        break;
                      }
                    }

                    latCtrl.text = lat.toString();
                    lngCtrl.text = lng.toString();
                    addressCtrl.text = result['formatted_address'] ?? description;
                    if (city.isNotEmpty) cityCtrl.text = city;

                    // Save google maps link
                    mapsUrlCtrl.text = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
                  }
                }
              } catch (e) {
                debugPrint('Place details error: $e');
                _showSnackBar('Failed to fetch location.', Colors.red);
              } finally {
                setDialogState(() => isFetchingLocation = false);
              }
            }

            Future<void> pickTime(bool isOpen) async {
              final TimeOfDay? picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
                builder: (context, child) => Theme(
                  data: ThemeData.light().copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: Colors.black,
                      onPrimary: Colors.white,
                      surface: Colors.white,
                    ),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) {
                final formatted =
                    "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:00";
                setDialogState(() {
                  if (isOpen) {
                    openTime = formatted;
                  } else {
                    closeTime = formatted;
                  }
                });
              }
            }

            Future<void> pickPhoto(String kind) async {
              try {
                final picker = ImagePicker();
                final picked = await picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 80,
                );
                if (picked == null) return;

                setDialogState(() {
                  if (kind == 'entry') {
                    newEntryPhoto = File(picked.path);
                    existingEntryPhotoUrl = null;
                  } else if (kind == 'exit') {
                    newExitPhoto = File(picked.path);
                    existingExitPhotoUrl = null;
                  } else {
                    newAreaPhotos.add(File(picked.path));
                  }
                });
              } catch (e) {
                debugPrint('Picker error: $e');
                _showSnackBar('Failed to pick image: $e', Colors.red);
              }
            }

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              insetPadding: const EdgeInsets.all(20),
              child: Container(
                width: isMobile ? double.infinity : 700,
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(isEditing ? Icons.edit : Icons.add_business,
                                  color: Colors.orange, size: 24),
                              const SizedBox(width: 10),
                              Text(
                                isEditing ? 'Edit Parking Space' : 'Add New Parking Space',
                                style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.black54),
                            onPressed: () {
                              debounce?.cancel();
                              Navigator.pop(dialogCtx);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      _buildResponsiveRow(
                        isMobile,
                        _buildDialogInput('Parking Name *', nameCtrl, 'e.g., Downtown Parking'),
                        _buildDialogDropdown('Parking Type *', type, typeOptions,
                                (val) => setDialogState(() => type = val!)),
                      ),
                      const SizedBox(height: 16),

                      // ==================================================
                      // ADDRESS WITH AUTOCOMPLETE
                      // ==================================================
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Address *',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: addressCtrl,
                            maxLines: 1,
                            style: const TextStyle(color: Colors.black, fontSize: 14),
                            onChanged: (val) {
                              if (debounce?.isActive ?? false) debounce!.cancel();
                              debounce = Timer(const Duration(milliseconds: 350), () {
                                fetchAddressSuggestions(val);
                              });
                            },
                            decoration: InputDecoration(
                              hintText: 'Start typing your address...',
                              hintStyle: TextStyle(color: Colors.grey.shade500),
                              prefixIcon: isFetchingLocation
                                  ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                                  : const Icon(Icons.location_on, color: Colors.red, size: 18),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey.shade400)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              isDense: true,
                            ),
                          ),
                          // Suggestion list
                          if (addressSuggestions.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              constraints: const BoxConstraints(maxHeight: 220),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ListView.separated(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: addressSuggestions.length,
                                separatorBuilder: (_, __) =>
                                    Divider(height: 1, color: Colors.grey.shade200),
                                itemBuilder: (context, i) {
                                  final s = addressSuggestions[i];
                                  return InkWell(
                                    onTap: () => applyPlace(
                                        s['place_id'].toString(),
                                        s['description'].toString()),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      child: Row(
                                        children: [
                                          Icon(Icons.place_outlined,
                                              color: Colors.grey.shade600, size: 18),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  s['structured_formatting']
                                                  ?['main_text'] ??
                                                      s['description'] ??
                                                      '',
                                                  style: const TextStyle(
                                                      color: Colors.black,
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                if ((s['structured_formatting']
                                                ?['secondary_text'] ??
                                                    '')
                                                    .toString()
                                                    .isNotEmpty)
                                                  Text(
                                                    s['structured_formatting']
                                                    ['secondary_text'],
                                                    style: TextStyle(
                                                        color: Colors.grey.shade600,
                                                        fontSize: 11),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          const SizedBox(height: 6),
                          Text(
                            'Select from suggestions — latitude & longitude will be filled automatically.',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // City only (lat/lng hidden)
                      _buildDialogInput('City *', cityCtrl, 'e.g., Mumbai'),
                      const SizedBox(height: 16),

                      // ✅ HIDDEN lat/lng — kept in memory only
                      if (latCtrl.text.isNotEmpty && lngCtrl.text.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle,
                                  color: Colors.green.shade700, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Location captured: ${latCtrl.text}, ${lngCtrl.text}',
                                  style: TextStyle(
                                      color: Colors.green.shade800,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),

                      _buildResponsiveRow(
                        isMobile,
                        _buildDialogInput('Car Capacity', carCtrl, '0', isNum: true),
                        _buildDialogInput('Bike Capacity', bikeCtrl, '0', isNum: true),
                      ),
                      const SizedBox(height: 16),

                      _buildResponsiveRow(
                        isMobile,
                        _buildDialogInput('SUV Capacity', suvCtrl, '0', isNum: true),
                        _buildDialogInput('EV Capacity', evCtrl, '0', isNum: true),
                      ),
                      const SizedBox(height: 16),

                      _buildResponsiveRow(
                        isMobile,
                        _buildTimePicker('Open Time *', openTime, () => pickTime(true)),
                        _buildTimePicker('Close Time *', closeTime, () => pickTime(false)),
                      ),
                      const SizedBox(height: 24),

                      const Text('Amenities',
                          style: TextStyle(
                              color: Colors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: _amenitiesList.map((amenity) {
                          final isSelected = selectedAmenities.contains(amenity['key']);
                          return InkWell(
                            onTap: () {
                              setDialogState(() {
                                if (isSelected) {
                                  selectedAmenities.remove(amenity['key']);
                                } else {
                                  selectedAmenities.add(amenity['key']);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: isMobile
                                  ? (MediaQuery.of(context).size.width - 100) / 2
                                  : 150,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: isSelected
                                        ? Colors.blue
                                        : Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                    color: isSelected
                                        ? Colors.blue
                                        : Colors.grey.shade500,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(amenity['icon'],
                                      color: amenity['color'], size: 14),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      amenity['label'],
                                      style: TextStyle(
                                          color: isSelected
                                              ? Colors.black
                                              : Colors.grey.shade600,
                                          fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 6),
                      Text('Select all applicable amenities',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),

                      const SizedBox(height: 24),

                      // ==================================================
                      // LOCATION VERIFICATION PHOTOS
                      // ==================================================
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.withOpacity(0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.verified,
                                    color: Colors.blue.shade700, size: 18),
                                const SizedBox(width: 8),
                                const Text(
                                  'Location Verification (Optional)',
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Upload photos to verify your parking location.',
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 11),
                            ),
                            const SizedBox(height: 16),

                            _buildPhotoUpload(
                              label: 'Entry Photo',
                              icon: Icons.login,
                              newFile: newEntryPhoto,
                              existingUrl: existingEntryPhotoUrl,
                              onTap: () => pickPhoto('entry'),
                            ),
                            const SizedBox(height: 12),

                            _buildPhotoUpload(
                              label: 'Exit Photo',
                              icon: Icons.logout,
                              newFile: newExitPhoto,
                              existingUrl: existingExitPhotoUrl,
                              onTap: () => pickPhoto('exit'),
                            ),
                            const SizedBox(height: 12),

                            _buildAreaPhotosUpload(
                              newFiles: newAreaPhotos,
                              existingUrls: existingAreaPhotos,
                              onAdd: () => pickPhoto('area'),
                              onRemoveNew: (i) =>
                                  setDialogState(() => newAreaPhotos.removeAt(i)),
                              onRemoveExisting: (i) =>
                                  setDialogState(() => existingAreaPhotos.removeAt(i)),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),
                      Wrap(
                        spacing: 12,
                        children: [
                          ElevatedButton.icon(
                            onPressed: isSaving
                                ? null
                                : () async {
                              debounce?.cancel();

                              if (nameCtrl.text.isEmpty ||
                                  type == 'Select Type' ||
                                  addressCtrl.text.isEmpty ||
                                  cityCtrl.text.isEmpty ||
                                  latCtrl.text.isEmpty ||
                                  lngCtrl.text.isEmpty ||
                                  openTime.contains('--') ||
                                  closeTime.contains('--')) {
                                _showSnackBar(
                                    'Please fill all required (*) fields and select an address from suggestions.',
                                    Colors.orange);
                                return;
                              }

                              setDialogState(() => isSaving = true);
                              try {
                                final uri = Uri.parse(
                                    'https://parkfro.com/API.php?table=parking_spaces');

                                final hasNewPhotos = newEntryPhoto != null ||
                                    newExitPhoto != null ||
                                    newAreaPhotos.isNotEmpty;

                                if (hasNewPhotos) {
                                  // Use POST + _method=PUT so PHP parses files
                                  var request = http.MultipartRequest('POST', uri);

                                  request.fields['owner_id'] = _ownerId ?? '1';
                                  request.fields['name'] = nameCtrl.text;
                                  request.fields['address'] = addressCtrl.text;
                                  request.fields['city'] = cityCtrl.text;
                                  request.fields['type'] = type.toLowerCase();
                                  request.fields['latitude'] = latCtrl.text;
                                  request.fields['longitude'] = lngCtrl.text;
                                  request.fields['google_maps_url'] = mapsUrlCtrl.text;
                                  request.fields['car_capacity'] = carCtrl.text;
                                  request.fields['bike_capacity'] = bikeCtrl.text;
                                  request.fields['ev_capacity'] = evCtrl.text;
                                  request.fields['suv_capacity'] = suvCtrl.text;
                                  request.fields['open_time'] = openTime;
                                  request.fields['close_time'] = closeTime;
                                  request.fields['amenities'] =
                                      json.encode(selectedAmenities);
                                  request.fields['status'] = 'pending';

                                  if (isEditing) {
                                    request.fields['id'] = parking['id'].toString();
                                    request.fields['_method'] = 'PUT';
                                  }

                                  if (newEntryPhoto != null) {
                                    request.files.add(await http.MultipartFile.fromPath(
                                        'entry_photo', newEntryPhoto!.path));
                                  } else if (existingEntryPhotoUrl != null) {
                                    request.fields['entry_photo'] =
                                    existingEntryPhotoUrl!;
                                  }

                                  if (newExitPhoto != null) {
                                    request.files.add(await http.MultipartFile.fromPath(
                                        'exit_photo', newExitPhoto!.path));
                                  } else if (existingExitPhotoUrl != null) {
                                    request.fields['exit_photo'] =
                                    existingExitPhotoUrl!;
                                  }

                                  // Preserve existing area photos
                                  if (existingAreaPhotos.isNotEmpty) {
                                    request.fields['area_photos'] =
                                        json.encode(existingAreaPhotos);
                                  }

                                  for (int i = 0; i < newAreaPhotos.length; i++) {
                                    request.files.add(await http.MultipartFile.fromPath(
                                        'area_photo_$i', newAreaPhotos[i].path));
                                  }

                                  final streamed = await request.send();
                                  final response =
                                  await http.Response.fromStream(streamed);

                                  if (response.statusCode == 200) {
                                    Navigator.pop(dialogCtx);
                                    _showSnackBar(
                                        isEditing
                                            ? 'Parking updated successfully!'
                                            : 'Parking added successfully!',
                                        Colors.green);
                                    _fetchParkings();
                                  } else {
                                    _showSnackBar(
                                        'Server Error: ${response.statusCode}',
                                        Colors.red);
                                  }
                                } else {
                                  // No new photos — use JSON
                                  final bodyData = {
                                    'owner_id': _ownerId ?? '1',
                                    'name': nameCtrl.text,
                                    'address': addressCtrl.text,
                                    'city': cityCtrl.text,
                                    'type': type.toLowerCase(),
                                    'latitude': latCtrl.text,
                                    'longitude': lngCtrl.text,
                                    'google_maps_url': mapsUrlCtrl.text,
                                    'car_capacity': carCtrl.text,
                                    'bike_capacity': bikeCtrl.text,
                                    'ev_capacity': evCtrl.text,
                                    'suv_capacity': suvCtrl.text,
                                    'open_time': openTime,
                                    'close_time': closeTime,
                                    'amenities': json.encode(selectedAmenities),
                                    'status': 'pending',
                                  };

                                  if (existingAreaPhotos.isNotEmpty) {
                                    bodyData['area_photos'] =
                                        json.encode(existingAreaPhotos);
                                  }

                                  http.Response response;
                                  if (isEditing) {
                                    bodyData['id'] = parking['id'].toString();
                                    response = await http.put(
                                      uri,
                                      headers: {
                                        'Content-Type': 'application/json'
                                      },
                                      body: json.encode(bodyData),
                                    );
                                  } else {
                                    response = await http.post(
                                      uri,
                                      headers: {
                                        'Content-Type':
                                        'application/x-www-form-urlencoded'
                                      },
                                      body: bodyData,
                                    );
                                  }

                                  if (response.statusCode == 200) {
                                    Navigator.pop(dialogCtx);
                                    _showSnackBar(
                                        isEditing
                                            ? 'Parking updated successfully!'
                                            : 'Parking added successfully!',
                                        Colors.green);
                                    _fetchParkings();
                                  } else {
                                    _showSnackBar(
                                        'Server Error: ${response.statusCode}',
                                        Colors.red);
                                  }
                                }
                              } catch (e) {
                                debugPrint('Save error: $e');
                                _showSnackBar('Network Error: $e', Colors.red);
                              } finally {
                                if (mounted) {
                                  setDialogState(() => isSaving = false);
                                }
                              }
                            },
                            icon: isSaving
                                ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                                : const Icon(Icons.save, color: Colors.white, size: 20),
                            label: Text(
                              isSaving
                                  ? 'Saving...'
                                  : (isEditing ? 'Update Parking' : 'Submit for Approval'),
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () {
                              debounce?.cancel();
                              Navigator.pop(dialogCtx);
                            },
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey.shade300),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Cancel',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==================================================
  // PHOTO UPLOAD WIDGETS
  // ==================================================
  Widget _buildPhotoUpload({
    required String label,
    required IconData icon,
    required File? newFile,
    required String? existingUrl,
    required VoidCallback onTap,
  }) {
    final hasFile = newFile != null || (existingUrl != null && existingUrl.isNotEmpty);

    ImageProvider? bgImage;
    if (newFile != null) {
      bgImage = FileImage(newFile);
    } else if (existingUrl != null && existingUrl.isNotEmpty) {
      bgImage = NetworkImage(existingUrl);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasFile ? Colors.green : Colors.grey.shade300,
            width: hasFile ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                image: bgImage != null
                    ? DecorationImage(
                  image: bgImage,
                  fit: BoxFit.cover,
                  onError: (_, __) {},
                )
                    : null,
              ),
              child: !hasFile
                  ? Icon(icon, color: Colors.grey.shade500, size: 24)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hasFile ? 'Tap to change' : 'Tap to upload photo',
                    style: TextStyle(
                        color:
                        hasFile ? Colors.green.shade700 : Colors.grey.shade600,
                        fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(
              hasFile ? Icons.check_circle : Icons.add_a_photo,
              color: hasFile ? Colors.green : Colors.grey.shade500,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAreaPhotosUpload({
    required List<File> newFiles,
    required List<String> existingUrls,
    required VoidCallback onAdd,
    required Function(int) onRemoveNew,
    required Function(int) onRemoveExisting,
  }) {
    final total = newFiles.length + existingUrls.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Parking Area Photos ($total)',
              style: const TextStyle(
                  color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_photo_alternate,
                  color: Colors.blue, size: 16),
              label: const Text('Add Photo',
                  style:
                  TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (total == 0)
          Container(
            padding: const EdgeInsets.all(20),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                Icon(Icons.photo_library_outlined,
                    color: Colors.grey.shade400, size: 32),
                const SizedBox(height: 6),
                Text(
                  'No photos added yet',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...newFiles.asMap().entries.map((e) => _buildPhotoThumb(
                image: FileImage(e.value),
                onRemove: () => onRemoveNew(e.key),
              )),
              ...existingUrls.asMap().entries.map((e) => _buildPhotoThumb(
                image: NetworkImage(e.value),
                onRemove: () => onRemoveExisting(e.key),
              )),
            ],
          ),
      ],
    );
  }

  Widget _buildPhotoThumb({
    required ImageProvider image,
    required VoidCallback onRemove,
  }) {
    return Stack(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey.shade200,
            image: DecorationImage(image: image, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: InkWell(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 12),
            ),
          ),
        ),
      ],
    );
  }

  String _prettyStatus(String status) {
    if (status.isEmpty) return 'PENDING';
    if (status.length == 1) return status.toUpperCase();
    return status[0].toUpperCase() + status.substring(1).toLowerCase();
  }

  Widget _buildResponsiveRow(bool isMobile, Widget field1, Widget field2) {
    if (isMobile) return Column(children: [field1, const SizedBox(height: 16), field2]);
    return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: field1),
          const SizedBox(width: 16),
          Expanded(child: field2),
        ]);
  }

  Widget _buildDialogInput(String label, TextEditingController ctrl, String hint,
      {bool isNum = false, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          keyboardType: isNum
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          style: const TextStyle(color: Colors.black, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade500),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade400)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildDialogDropdown(String label, String value, List<String> options,
      Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
              color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: Colors.white,
              style: const TextStyle(color: Colors.black, fontSize: 14),
              items: options
                  .map((String opt) => DropdownMenuItem(
                  value: opt,
                  child: Text(opt == 'Select Type'
                      ? opt
                      : opt[0].toUpperCase() + opt.substring(1))))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimePicker(String label, String timeStr, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
                color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                      color: timeStr.contains('--')
                          ? Colors.grey.shade500
                          : Colors.black,
                      fontSize: 14),
                ),
                Icon(Icons.access_time, color: Colors.grey.shade600, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.grey.shade50,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context)),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: const [
                          Icon(Icons.local_parking, color: Colors.blue, size: 28),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'My Parking Spaces',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _showParkingDialog(),
                      icon: const Icon(Icons.add, color: Colors.white, size: 18),
                      label: const Text('Add New',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8))),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Manage and monitor all your listed parking spaces',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 24),

                _isLoading
                    ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                        child: CircularProgressIndicator(color: Colors.blue)))
                    : _parkings.isEmpty
                    ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300)),
                  child: const Center(
                      child: Text('You have no parking spaces yet.',
                          style: TextStyle(color: Colors.black54))),
                )
                    : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _parkings.length,
                  itemBuilder: (context, index) =>
                      _buildParkingCard(_parkings[index]),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
          if (_isLoading)
            Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                    backgroundColor: Colors.grey.shade200,
                    color: Colors.blue,
                    minHeight: 3)),
        ],
      ),
    );
  }

  Widget _buildParkingCard(Map<String, dynamic> parking) {
    String status = parking['status']?.toString().toUpperCase() ?? 'PENDING';
    if (status.isEmpty) status = 'PENDING';

    Color statusColor = Colors.orange.shade700;
    Color statusBg = Colors.orange.withOpacity(0.1);
    if (status == 'APPROVED') {
      statusColor = Colors.green.shade700;
      statusBg = Colors.green.withOpacity(0.1);
    }
    if (status == 'REJECTED') {
      statusColor = Colors.red;
      statusBg = Colors.red.withOpacity(0.1);
    }

    List<String> amenities = [];
    try {
      if (parking['amenities'] != null) {
        amenities = List<String>.from(json.decode(parking['amenities']));
      }
    } catch (_) {}

    // ✅ Photo preview URLs
    final entryPhoto = _resolveImageUrl(parking['entry_photo']?.toString());
    final exitPhoto = _resolveImageUrl(parking['exit_photo']?.toString());
    List<String> areaPhotos = [];
    try {
      if (parking['area_photos'] != null) {
        final parsed = json.decode(parking['area_photos'].toString());
        if (parsed is List) {
          areaPhotos = parsed.map((e) => _resolveImageUrl(e.toString())).where((e) => e.isNotEmpty).toList();
        }
      }
    } catch (_) {}

    int photoCount = 0;
    if (entryPhoto.isNotEmpty) photoCount++;
    if (exitPhoto.isNotEmpty) photoCount++;
    photoCount += areaPhotos.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                    child: Text(parking['name'] ?? 'Unknown Parking',
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withOpacity(0.4))),
                  child: Text(_prettyStatus(status),
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Divider(color: Colors.grey.shade200, height: 1),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildInfoRow(Icons.location_on, Colors.pink, 'Location',
                    '${parking['address'] ?? ''}, ${parking['city'] ?? ''}'),
                const SizedBox(height: 12),
                _buildInfoRow(Icons.category, Colors.grey.shade600, 'Type',
                    (parking['type'] ?? 'N/A').toString().toUpperCase()),
                const SizedBox(height: 12),
                _buildInfoRow(Icons.access_time, Colors.grey.shade600, 'Timing',
                    '${parking['open_time']} - ${parking['close_time']}'),
                const SizedBox(height: 12),
                _buildInfoRow(Icons.directions_car, Colors.red, 'Capacity',
                    'Car: ${parking['car_capacity'] ?? 0} | Bike: ${parking['bike_capacity'] ?? 0}'),
                const SizedBox(height: 4),
                _buildInfoRow(Icons.electric_car, Colors.purple, 'EV/SUV',
                    'EV: ${parking['ev_capacity'] ?? 0} | SUV: ${parking['suv_capacity'] ?? 0}'),

                if ((parking['google_maps_url']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildInfoRow(Icons.map, Colors.green.shade700, 'Maps',
                      'Google Maps link added'),
                ],

                if (photoCount > 0) ...[
                  const SizedBox(height: 12),
                  _buildInfoRow(Icons.photo_library, Colors.indigo, 'Photos',
                      '$photoCount photos'),
                ],

                // ✅ Photo preview strip
                if (entryPhoto.isNotEmpty ||
                    exitPhoto.isNotEmpty ||
                    areaPhotos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 70,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        if (entryPhoto.isNotEmpty)
                          _buildCardThumb(entryPhoto, 'Entry'),
                        if (exitPhoto.isNotEmpty)
                          _buildCardThumb(exitPhoto, 'Exit'),
                        ...areaPhotos.map((u) => _buildCardThumb(u, 'Area')),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                if (amenities.isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.stars, color: Colors.red, size: 16),
                      const SizedBox(width: 12),
                      SizedBox(
                          width: 80,
                          child: Text('Amenities',
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 13))),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: amenities.map((aKey) {
                            final def = _amenitiesList.firstWhere(
                                    (element) => element['key'] == aKey,
                                orElse: () => {
                                  'label': aKey,
                                  'icon': Icons.check,
                                  'color': Colors.black87
                                });
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                  border:
                                  Border.all(color: Colors.grey.shade300)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(def['icon'],
                                      color: def['color'], size: 12),
                                  const SizedBox(width: 4),
                                  Text(def['label'],
                                      style: const TextStyle(
                                          color: Colors.black87, fontSize: 11)),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          Divider(color: Colors.grey.shade200, height: 1),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_month, color: Colors.blue, size: 14),
                    const SizedBox(width: 6),
                    Text(parking['created_at']?.toString().split(' ')[0] ?? '',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
                InkWell(
                  onTap: () => _showParkingDialog(parking: parking),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      children: const [
                        Icon(Icons.edit, color: Colors.orange, size: 14),
                        SizedBox(width: 6),
                        Text('Edit',
                            style: TextStyle(
                                color: Colors.black87,
                                fontSize: 13,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardThumb(String url, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: Colors.grey.shade200,
              image: DecorationImage(
                image: NetworkImage(url),
                fit: BoxFit.cover,
                onError: (_, __) {},
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, Color iconColor, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 16),
        const SizedBox(width: 12),
        SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.right)),
      ],
    );
  }
}