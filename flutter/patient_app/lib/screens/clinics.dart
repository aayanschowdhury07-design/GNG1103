import 'package:clinicflow_core/clinicflow_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../scope.dart';
import '../widgets.dart';
import 'booking.dart';

enum _Filter { accepting, today, all }

/// The ClinicFlow clinic directory: a map and a list of the same clinics, nearest first,
/// with the next opening read from each clinic's own schedule.
class ClinicsScreen extends StatefulWidget {
  const ClinicsScreen({super.key, this.standalone = false});

  /// True when pushed from the booking flow (back button), false as a tab.
  final bool standalone;
  @override
  State<ClinicsScreen> createState() => _ClinicsScreenState();
}

class _ClinicsScreenState extends State<ClinicsScreen> {
  final _map = MapController();
  final _search = TextEditingController();
  _Filter _filter = _Filter.accepting;
  String? _selected;

  // the patient's location in the sample data
  static const _me = LatLng(43.6745, -79.3905);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _select(Clinic c) {
    setState(() => _selected = c.id);
    _map.move(LatLng(c.lat, c.lng), _map.camera.zoom);
  }

  void _book(Clinic c) {
    context.draft.start(context.backend, c.id);
    final nav = Navigator.of(context);
    if (widget.standalone) {
      nav.pop(); // back to step 1, now set to this clinic
    } else {
      nav.push(MaterialPageRoute(builder: (_) => const BookServiceScreen()));
    }
  }

  void _waitlist(Clinic c) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Added to ${c.name}'s waitlist. They'll text you if a time opens.")),
      );

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final b = context.backend, c = context.colors;
      final term = _search.text.trim().toLowerCase().replaceAll(RegExp(r'therapy$'), '');
      final list = b.clinics
          .where((x) => term.isEmpty || '${x.name} ${x.kind}'.toLowerCase().contains(term))
          .where((x) => switch (_filter) {
                _Filter.accepting => x.accepting,
                _Filter.today => b.nextOpening(x.id)?.date == b.today,
                _Filter.all => true,
              })
          .toList()
        ..sort((x, y) => b.distanceKm(x).compareTo(b.distanceKm(y)));
      final selected = list.where((x) => x.id == _selected).firstOrNull;

      String nextText(Clinic x) {
        if (!x.accepting) return 'Waitlist only';
        final n = b.nextOpening(x.id);
        return n == null ? 'No openings in the next 2 weeks' : 'Next opening ${dayLabel(n.date, b.today, midSentence: true)} ${formatTime(n.minute)}';
      }

      Widget action(Clinic x, {bool primary = false}) {
        final open = x.accepting && b.nextOpening(x.id) != null;
        if (!open) return TextButton(onPressed: () => _waitlist(x), child: const Text('Join waitlist'));
        return primary
            ? FilledButton(onPressed: () => _book(x), child: const Text('Book'))
            : TextButton(onPressed: () => _book(x), child: Semantics(label: 'Book at ${x.name}', child: const Text('Book')));
      }

      return ScreenFrame(
        back: widget.standalone,
        title: 'Clinics near you',
        children: [
          TextField(
            controller: _search,
            decoration: const InputDecoration(labelText: 'Service or clinic', hintText: 'e.g. physiotherapy', prefixIcon: Icon(Icons.search)),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          UnderlineTabs<_Filter>(
            label: 'Filter clinics',
            options: const [(_Filter.accepting, 'Accepting patients'), (_Filter.today, 'Openings today'), (_Filter.all, 'All')],
            selected: _filter,
            onSelect: (f) => setState(() => _filter = f),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'Map of nearby clinics. The same clinics are listed below.',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 240,
                child: FlutterMap(
                  mapController: _map,
                  options: const MapOptions(
                    initialCenter: LatLng(43.665, -79.389),
                    initialZoom: 12,
                    interactionOptions: InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'ca.clinicflow.patient',
                      // muted to sit inside the app's palette; inverted in dark mode
                      tileBuilder: Theme.of(context).brightness == Brightness.dark ? darkModeTileBuilder : _mutedTile,
                    ),
                    MarkerLayer(markers: [
                      Marker(point: _me, width: 22, height: 22, child: _MeDot(color: c.stArrived, ring: c.surface)),
                      for (final x in list)
                        Marker(
                          point: LatLng(x.lat, x.lng),
                          width: 44,
                          height: 44,
                          child: _Pin(clinic: x, selected: x.id == _selected, onTap: () => _select(x)),
                        ),
                    ]),
                    const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (selected == null)
            Text('Tap a pin to see that clinic’s next opening.', style: context.text.bodySmall)
          else
            Semantics(
              liveRegion: true,
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(selected.name, style: context.text.titleMedium),
                    Text('${selected.address} · ${b.distanceKm(selected)} km · ${selected.kind}', style: context.text.bodySmall),
                    Text(nextText(selected), style: context.text.bodySmall?.copyWith(color: b.nextOpening(selected.id) != null ? c.good : c.muted)),
                  ]),
                ),
                action(selected, primary: true),
              ]),
            ),
          Section(
            child: Column(children: [
              if (list.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text('No clinics match. Try "physio" or switch the filter to All.', style: context.text.bodySmall)),
              for (final x in list)
                Container(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: x.id == _selected ? c.accent : c.line, width: x.id == _selected ? 2 : 1))),
                  child: Row(children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _select(x),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text.rich(TextSpan(children: [
                              TextSpan(text: x.name, style: TextStyle(fontWeight: FontWeight.w500, color: x.id == _selected ? c.accent : c.fg)),
                              if (x.isHome) TextSpan(text: '  Your clinic', style: context.text.labelMedium?.copyWith(color: c.accent)),
                            ])),
                            Text('${b.distanceKm(x)} km · ${x.kind}', style: context.text.bodySmall),
                            Text(nextText(x), style: context.text.bodySmall?.copyWith(color: b.nextOpening(x.id) != null ? c.good : c.muted)),
                          ]),
                        ),
                      ),
                    ),
                    action(x),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          Text('Clinics opt in to the directory. Only availability is shared, never the reason for your visit.', style: context.text.bodySmall),
        ],
      );
    });
  }
}

Widget _mutedTile(BuildContext context, Widget tile, TileImage image) => ColorFiltered(
      // 30% saturation: the streets stay readable without competing with the pins
      colorFilter: const ColorFilter.matrix([
        0.5574, 0.5023, 0.0503, 0, 0,
        0.1489, 0.9108, 0.0503, 0, 0,
        0.1489, 0.5023, 0.4588, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: tile,
    );

class _Pin extends StatelessWidget {
  const _Pin({required this.clinic, required this.selected, required this.onTap});
  final Clinic clinic;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors, open = clinic.accepting;
    return Semantics(
      button: true,
      selected: selected,
      label: clinic.name,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1.15 : 1,
          duration: const Duration(milliseconds: 160),
          child: Container(
            margin: const EdgeInsets.all(4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: open ? c.accent : c.surface,
              border: Border.all(color: selected ? c.fg : (open ? c.surface : c.lineStrong), width: selected ? 3 : 2),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Text(clinic.initials, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: open ? c.accentFg : c.muted)),
          ),
        ),
      ),
    );
  }
}

class _MeDot extends StatelessWidget {
  const _MeDot({required this.color, required this.ring});
  final Color color, ring;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'You are here',
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: ring, width: 3),
            boxShadow: [BoxShadow(color: color.withValues(alpha: .25), spreadRadius: 5)],
          ),
        ),
      );
}
