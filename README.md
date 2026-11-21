# Editor Grid Streaming

Addon para abrir mapas particionados no editor do Godot. Ele carrega as cenas ao redor da câmera 3D principal e reaproveita as células que continuam dentro do raio quando a câmera cruza uma borda.

## Instalação

1. Copie `addons/editor_grid_streaming` para a pasta `addons/` do seu projeto.
2. Ative **Editor Grid Streaming** nas configurações de plugins do Godot.
3. Adicione um nó `EditorStreamingGrid3D` à cena do mapa e escolha a pasta das células em **Cells Directory**.

## Preparação do mapa

Salve cada célula com uma raiz `Node3D` em uma cena chamada `cell_<x>_<z>.tscn`. Por exemplo, `cell_0_0.tscn` e `cell_-1_2.tscn`. As coordenadas são inteiras no plano X/Z.

A origem da grade é a posição do nó `EditorStreamingGrid3D`. **Cell Size** define o lado de cada célula em metros. Modele cada partição em coordenadas locais à sua célula. O addon aplica o deslocamento da grade ao carregar a cena.

| Radius in Cells | Área carregada |
| --- | --- |
| 0 | Apenas a célula da câmera |
| 1 | Até 9 células em uma grade 3×3 |
| 2 | Até 25 células em uma grade 5×5 |
| r | Até (2r + 1)² células |

A seleção inclui diagonais e usa as cenas existentes na pasta. A célula da câmera tem prioridade na fila de carregamento.

## Edição

A cena do mapa mostra as prévias. Use **Edit Camera Cell** na barra do editor 3D para abrir e editar a cena da célula atual. Salve essa cena normalmente e volte à aba do mapa para ver o resultado. O mapa salva a configuração da grade e cada célula salva seu conteúdo.

## Validação

Testado no Godot 4.7.2. O teste usa um projeto temporário e abre o editor.

```bash
python3 tests/run_editor_test.py
```

No Linux sem um desktop disponível, execute com uma tela virtual.

```bash
xvfb-run -a python3 tests/run_editor_test.py
```
