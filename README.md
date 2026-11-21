# Editor Proximity Streaming

Addon para editar mapas grandes no Godot. Os prefabs entram sob demanda em uma área quadrada ao redor da câmera 3D principal do editor. Cada colocação continua editável na mesma cena do mapa.

## Instalação

1. Copie `addons/editor_proximity_streaming` para a pasta `addons/` do projeto.
2. Ative **Editor Proximity Streaming** nas configurações de plugins do Godot.
3. Adicione um nó `ProximityPreview3D` como filho direto da cena do mapa. Ajuste **Radius Meters** no Inspector. Por exemplo, 50 m definem uma área de 100 × 100 m no plano X/Z.
4. Para cada objeto carregado sob demanda, adicione um `ProximityPlacement3D` ao mapa. Defina **Scene Path** para seu prefab com raiz `Node3D` e ajuste a transformação da colocação.

## Edição

O addon carrega o prefab quando ele toca a área da câmera. Use o metadado opcional `stream_bounds` com uma `AABB` local à colocação para contabilizar a extensão do objeto. Por padrão, o alcance usa a origem da colocação.

Selecione e mova a colocação no mapa. Use **Open Prefab** no Inspector para editar a cena original. **Instance Properties** permite sobrescrever propriedades da raiz para uma colocação.

As prévias são carregadas pelo editor. Um projeto pode usar o caminho e a transformação das colocações com seu próprio carregador durante o jogo.

## Validação

Testado no Godot 4.7.2. O teste usa um projeto temporário e abre o editor.

```bash
python3 tests/run_editor_test.py
```

No Linux sem desktop, execute com uma tela virtual.

```bash
xvfb-run -a python3 tests/run_editor_test.py
```
