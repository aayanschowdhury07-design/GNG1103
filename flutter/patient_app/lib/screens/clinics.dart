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
  bool _locating = false, _locationOff = false;

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

  Future<void> _locate() async {
    setState(() => _locating = true);
    final ok = await shareLocation(context);
    if (!mounted) return;
    setState(() {
      _locating = false;
      _locationOff = !ok;
    });
    final here = context.backend.here;
    if (ok && here != null) _map.move(LatLng(here.lat, here.lng), 13);
  }

  @override
  Widget build(BuildContext context) {
    return Watch(builder: (context) {
      final b = context.backend, c = context.colors, s = context.s, lang = context.lang, here = b.here;
      if (b.clinics.isEmpty) {
        return ScreenFrame(back: widget.standalone, title: s.t('clinicsTitle'), children: [
          const SizedBox(height: 24),
          Text(s.t('noClinics'), style: context.text.titleMedium),
          const SizedBox(height: 4),
          Text(s.t('noClinicsSub'), style: context.text.bodySmall),
        ]);
      }
      final term = _search.text.trim().toLowerCase().replaceAll(RegExp(r'(therapy|thérapie)$'), '');
      final list = b.clinics
          .where((x) => term.isEmpty || '${x.name} ${x.kind}'.toLowerCase().contains(term))
          .where((x) => switch (_filter) {
                _Filter.accepting => x.accepting && x.bookable,
                _Filter.today => b.nextOpening(x.id)?.date == b.today,
                _Filter.all => true,
              })
          .toList()
        ..sort(b.byDistance);
      final selected = list.where((x) => x.id == _selected).firstOrNull;
      // without the patient's location, the map opens over the middle of the clinics
      final all = b.clinics;
      final centre = here != null
          ? LatLng(here.lat, here.lng)
          : LatLng(all.map((x) => x.lat).reduce((a, z) => a + z) / all.length, all.map((x) => x.lng).reduce((a, z) => a + z) / all.length);

      String details(Clinic x) {
        final km = b.distanceKm(x);
        return [if (km != null) distanceText(km), x.kind].join(' · ');
      }

      String nextText(Clinic x) {
        if (!x.accepting || !x.bookable) return s.t('waitOnly');
        final n = b.nextOpening(x.id);
        return n == null ? s.t('noneSoon') : s.t('nextOpening', {'when': '${dayLabel(n.date, b.today, lang: lang, midSentence: true)} ${formatTime(n.minute, lang: lang)}'});
      }

      // clinics that aren't taking online bookings say why instead of showing a button
      Widget? action(Clinic x, {bool primary = false}) {
        if (b.nextOpening(x.id) == null) return null;
        return primary
            ? FilledButton(onPressed: () => _book(x), child: Text(s.t('book')))
            : TextButton(onPressed: () => _book(x), child: Semantics(label: s.t('bookAt', {'name': x.name}), child: Text(s.t('book'))));
      }

      return ScreenFrame(
        back: widget.standalone,
        title: s.t('clinicsTitle'),
        children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(labelText: s.t('search'), hintText: s.t('searchHint'), prefixIcon: const Icon(Icons.search)),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          UnderlineTabs<_Filter>(
            label: s.t('filterLabel'),
            options: [(_Filter.accepting, s.t('fAccepting')), (_Filter.today, s.t('fToday')), (_Filter.all, s.t('fAll'))],
            selected: _filter,
            onSelect: (f) => setState(() => _filter = f),
          ),
          if (here == null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text(s.t(_locationOff ? 'locationOff' : 'shareLocation'), style: context.text.bodySmall)),
              TextButton.icon(
                onPressed: _locating ? null : _locate,
                icon: const Icon(Icons.my_location, size: 18),
                label: Text(s.t(_locating ? 'locating' : 'useLocation')),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          Semantics(
            label: s.t('mapLabel'),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 240,
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: centre,
                    initialZoom: 12,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'ca.clinicflow.patient',
                      // muted to sit inside the app's palette; inverted in dark mode
                      tileBuilder: Theme.of(context).brightness == Brightness.dark ? darkModeTileBuilder : _mutedTile,
                    ),
                    MarkerLayer(markers: [
                      if (here != null) Marker(point: LatLng(here.lat, here.lng), width: 22, height: 22, child: _MeDot(color: c.stArrived, ring: c.surface, label: s.t('youAreHere'))),
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
            Text(s.t('tapPin'), style: context.text.bodySmall)
          else
            Semantics(
              liveRegion: true,
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(selected.name, style: context.text.titleMedium),
                    Text('${selected.address} · ${details(selected)}', style: context.text.bodySmall),
                    Text(nextText(selected), style: context.text.bodySmall?.copyWith(color: b.nextOpening(selected.id) != null ? c.good : c.muted)),
                  ]),
                ),
                ?action(selected, primary: true),
              ]),
            ),
          Section(
            child: Column(children: [
              if (list.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(s.t('noMatch'), style: context.text.bodySmall)),
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
                              if (x.isHome) TextSpan(text: '  ${s.t('yourClinicTag')}', style: context.text.labelMedium?.copyWith(color: c.accent)),
                            ])),
                            Text(details(x), style: context.text.bodySmall),
                            Text(nextText(x), style: context.text.bodySmall?.copyWith(color: b.nextOpening(x.id) != null ? c.good : c.muted)),
                          ]),
                        ),
                      ),
                    ),
                    ?action(x),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          Text(s.t('optIn'), style: context.text.bodySmall),
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
  const _MeDot({required this.color, required this.ring, required this.label});
  final Color color, ring;
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
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
