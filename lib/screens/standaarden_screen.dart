import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bedrijfsgegevens.dart';
import '../models/standaard.dart';
import '../providers/bedrijfsgegevens_provider.dart';
import '../providers/standaarden_provider.dart';

class StandaardenScreen extends StatelessWidget {
  const StandaardenScreen({super.key});

  Future<void> _openForm(BuildContext context, {Standaard? bestaand}) async {
    final provider = context.read<StandaardenProvider>();

    final result = await showDialog<({String titel, String tekst})>(
      context: context,
      builder: (_) => _StandaardFormDialog(bestaand: bestaand),
    );
    if (result == null) return;

    if (bestaand == null) {
      await provider.addStandaard(result.titel, result.tekst);
    } else {
      await provider.updateStandaard(bestaand.id, result.titel, result.tekst);
    }
  }

  Future<void> _verwijderen(BuildContext context, Standaard standaard) async {
    final provider = context.read<StandaardenProvider>();
    final bevestigd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Standaard verwijderen'),
        content: Text('Weet je zeker dat je "${standaard.titel}" wilt verwijderen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );

    if (bevestigd == true) {
      await provider.removeStandaard(standaard.id);
    }
  }

  Future<void> _openBedrijfForm(BuildContext context, {Bedrijfsgegevens? bestaand}) async {
    final provider = context.read<BedrijfsgegevensProvider>();

    final result = await showDialog<Bedrijfsgegevens>(
      context: context,
      builder: (_) => _BedrijfFormDialog(bestaand: bestaand),
    );
    if (result == null) return;

    if (bestaand == null) {
      await provider.addBedrijf(result);
    } else {
      await provider.updateBedrijf(result);
    }
  }

  Future<void> _bedrijfVerwijderen(BuildContext context, Bedrijfsgegevens bedrijf) async {
    final provider = context.read<BedrijfsgegevensProvider>();
    final bevestigd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bedrijf verwijderen'),
        content: Text('Weet je zeker dat je "${bedrijf.naam}" wilt verwijderen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );

    if (bevestigd == true) {
      await provider.removeBedrijf(bedrijf.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StandaardenProvider>();
    final bedrijfProvider = context.watch<BedrijfsgegevensProvider>();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text('Bedrijfsgegevens', style: theme.textTheme.titleLarge),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _openBedrijfForm(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nieuw bedrijf'),
              ),
            ],
          ),
        ),
        if (bedrijfProvider.isLoaded && bedrijfProvider.bedrijven.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final bedrijf in bedrijfProvider.bedrijven)
                  SizedBox(
                    width: 340,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _LogoPreview(base64: bedrijf.logoBase64),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(bedrijf.naam,
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                  if (bedrijf.adres.isNotEmpty) Text(bedrijf.adres),
                                  if (bedrijf.postcodePlaats.isNotEmpty)
                                    Text(bedrijf.postcodePlaats),
                                  if (bedrijf.contactpersoon.isNotEmpty)
                                    Text(bedrijf.contactpersoon),
                                  if (bedrijf.telefoon.isNotEmpty) Text(bedrijf.telefoon),
                                  if (bedrijf.email.isNotEmpty) Text(bedrijf.email),
                                ],
                              ),
                            ),
                            Column(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  tooltip: 'Bewerken',
                                  onPressed: () =>
                                      _openBedrijfForm(context, bestaand: bedrijf),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  tooltip: 'Verwijderen',
                                  onPressed: () => _bedrijfVerwijderen(context, bedrijf),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Divider(height: 1),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text('Standaarden', style: theme.textTheme.titleLarge),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _openForm(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nieuwe standaard'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: !provider.isLoaded
              ? const Center(child: CircularProgressIndicator())
              : provider.standaarden.isEmpty
                  ? _EmptyState(theme: theme)
                  : Scrollbar(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: provider.standaarden.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final standaard = provider.standaarden[index];
                          return Card(
                            child: ListTile(
                              title: Text(standaard.titel,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                standaard.tekst,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: 'Bewerken',
                                    onPressed: () =>
                                        _openForm(context, bestaand: standaard),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: 'Verwijderen',
                                    onPressed: () => _verwijderen(context, standaard),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

class _LogoPreview extends StatelessWidget {
  final String? base64;
  const _LogoPreview({required this.base64});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: base64 == null
          ? Icon(Icons.business_outlined, color: theme.colorScheme.outline)
          : Image.memory(base64Decode(base64!), fit: BoxFit.contain),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ThemeData theme;
  const _EmptyState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.rule_folder_outlined,
              size: 64, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'Nog geen standaarden toegevoegd',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Druk op "Nieuwe standaard" om er een aan te maken',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outlineVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _StandaardFormDialog extends StatefulWidget {
  final Standaard? bestaand;
  const _StandaardFormDialog({this.bestaand});

  @override
  State<_StandaardFormDialog> createState() => _StandaardFormDialogState();
}

class _StandaardFormDialogState extends State<_StandaardFormDialog> {
  late final _titelController =
      TextEditingController(text: widget.bestaand?.titel ?? '');
  late final _tekstController =
      TextEditingController(text: widget.bestaand?.tekst ?? '');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _titelController.dispose();
    _tekstController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.bestaand == null ? 'Nieuwe standaard' : 'Standaard bewerken'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titelController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Titel'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Titel is verplicht' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tekstController,
                decoration: const InputDecoration(
                  labelText: 'Tekst',
                  alignLabelWithHint: true,
                ),
                minLines: 5,
                maxLines: 12,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Tekst is verplicht' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuleren'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(
                context,
                (titel: _titelController.text.trim(), tekst: _tekstController.text.trim()),
              );
            }
          },
          child: const Text('Opslaan'),
        ),
      ],
    );
  }
}

class _BedrijfFormDialog extends StatefulWidget {
  final Bedrijfsgegevens? bestaand;
  const _BedrijfFormDialog({this.bestaand});

  @override
  State<_BedrijfFormDialog> createState() => _BedrijfFormDialogState();
}

class _BedrijfFormDialogState extends State<_BedrijfFormDialog> {
  late final _naamController = TextEditingController(text: widget.bestaand?.naam ?? '');
  late final _adresController = TextEditingController(text: widget.bestaand?.adres ?? '');
  late final _postcodePlaatsController =
      TextEditingController(text: widget.bestaand?.postcodePlaats ?? '');
  late final _telefoonController =
      TextEditingController(text: widget.bestaand?.telefoon ?? '');
  late final _emailController = TextEditingController(text: widget.bestaand?.email ?? '');
  late final _contactpersoonController =
      TextEditingController(text: widget.bestaand?.contactpersoon ?? '');
  final _formKey = GlobalKey<FormState>();
  late String? _logoBase64 = widget.bestaand?.logoBase64;

  @override
  void dispose() {
    _naamController.dispose();
    _adresController.dispose();
    _postcodePlaatsController.dispose();
    _telefoonController.dispose();
    _emailController.dispose();
    _contactpersoonController.dispose();
    super.dispose();
  }

  Future<void> _kiesLogo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    if (!mounted) return;
    setState(() => _logoBase64 = base64Encode(bytes));
  }

  @override
  Widget build(BuildContext context) {
    final bestaand = widget.bestaand;
    return AlertDialog(
      title: Text(bestaand == null ? 'Nieuw bedrijf' : 'Bedrijf bewerken'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _LogoPreview(base64: _logoBase64),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _kiesLogo,
                            icon: const Icon(Icons.image_outlined, size: 18),
                            label: Text(_logoBase64 == null ? 'Logo kiezen' : 'Logo wijzigen'),
                          ),
                          if (_logoBase64 != null)
                            TextButton(
                              onPressed: () => setState(() => _logoBase64 = null),
                              child: const Text('Logo verwijderen'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _naamController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Naam bedrijf'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Naam is verplicht' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _adresController,
                  decoration: const InputDecoration(labelText: 'Adres'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _postcodePlaatsController,
                  decoration: const InputDecoration(labelText: 'Postcode plaats'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefoonController,
                  decoration: const InputDecoration(labelText: 'Telefoon'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Mail'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _contactpersoonController,
                  decoration: const InputDecoration(labelText: 'Contactpersoon'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuleren'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final naam = _naamController.text.trim();
            final adres = _adresController.text.trim();
            final postcodePlaats = _postcodePlaatsController.text.trim();
            final telefoon = _telefoonController.text.trim();
            final email = _emailController.text.trim();
            final contactpersoon = _contactpersoonController.text.trim();
            final result = bestaand == null
                ? Bedrijfsgegevens(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    naam: naam,
                    adres: adres,
                    postcodePlaats: postcodePlaats,
                    telefoon: telefoon,
                    email: email,
                    contactpersoon: contactpersoon,
                    logoBase64: _logoBase64,
                  )
                : bestaand.copyWith(
                    naam: naam,
                    adres: adres,
                    postcodePlaats: postcodePlaats,
                    telefoon: telefoon,
                    email: email,
                    contactpersoon: contactpersoon,
                    logoBase64: _logoBase64,
                    clearLogo: _logoBase64 == null,
                  );
            Navigator.pop(context, result);
          },
          child: const Text('Opslaan'),
        ),
      ],
    );
  }
}
