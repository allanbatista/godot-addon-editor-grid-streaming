# Editor Proximity Streaming

Addon para editar mapas grandes no Godot. Os prefabs entram sob demanda em uma área quadrada ao redor da câmera 3D principal do editor. Cada colocação continua editável na mesma cena do mapa.

## Instalação

1. Copie `addons/editor_proximity_streaming` para a pasta `addons/` do projeto.
2. Ative **Editor Proximity Streaming** nas configurações de plugins do Godot.
3. Adicione um nó `ProximityPreview3D` como filho direto da cena do mapa.
4. Use um `ProximityPlacement3D` com **Scene Path** para cada prefab carregado sob demanda.

## Classes de distância

Edite **Distance Classes** no Inspector do nó `ProximityPreview3D`. Cada entrada usa X para carregar e Y para descarregar, em metros. A distância mede o quadrado no plano X/Z até os limites do objeto. **Radius Meters** é o alcance das colocações sem classe.

| Classe | Entrada | Saída |
| --- | ---: | ---: |
| `dist_near` | 5 m | 7 m |
| `dist_local` | 25 m | 32 m |
| `dist_mid` | 50 m | 60 m |
| `dist_away` | 100 m | 115 m |
| `dist_remote` | 200 m | 220 m |

Adicione classes ao dicionário com o nome e os valores da sua escolha. **Stream Class** na colocação sobrescreve a classe do prefab.

## Prefabs e interiores

Na raiz do prefab, use o metadado `stream_class` e os grupos `world_object` ou `interior_detail`. Salve a cena para atualizar `proximity_prefabs.json`. Esse arquivo pode ser compartilhado com o projeto. O addon consulta os dados do índice antes de solicitar a cena.

O metadado opcional `stream_bounds` é uma `AABB` local para contabilizar a extensão do objeto. A tag `interior_detail` também exige que a câmera esteja dentro de **Activation Volume** da colocação ou do `stream_volume` de um nó pai.

Um prefab grande pode registrar `stream_preview_path` na raiz com o caminho de uma prévia leve. Essa prévia pode conter outras colocações carregáveis. Divida os detalhes em cenas que só sejam referenciadas por caminho na prévia. Use **Open Prefab** para editar a cena original.

A leitura das cenas roda em segundo plano. A montagem e a remoção na árvore do editor são distribuídas com até uma operação por quadro. Use prévias pequenas para reduzir o custo de uma operação individual.

## Validação

Testado no Godot 4.7.2. O teste usa um projeto temporário e abre o editor.

```bash
python3 tests/run_editor_test.py
```

No Linux sem desktop, execute com uma tela virtual.

```bash
xvfb-run -a python3 tests/run_editor_test.py
```
