# Editor Proximity Streaming

Addon para navegar e editar cenas 3D no Godot. Instâncias distantes aparecem
como caixas simples. Clique na caixa para selecionar a instância original
e pressione **F** na vista 3D para focá-la.

## Instalação

1. Copie `addons/editor_proximity_streaming/` para o diretório `addons/`
   do seu projeto.
2. Em **Project → Project Settings → Plugins**, ative **Editor Proximity
   Streaming**.
3. Abra a cena em que pretende trabalhar e entre na vista **3D**.

Validado com Godot 4.7.2. A grade de protótipo é gerada pelo shader do addon.

## Configure uma instância

1. Instancie o prefab na cena como de costume.
2. No menu de contexto da instância, marque **Load as Placeholder**.
3. Na raiz do prefab, atribua uma das classes de distância como grupo ou
   use o metadado `stream_class`. Para sobrescrever a classe de uma
   colocação específica, use `stream_class` nessa instância.

O grupo `world_object` equivale a `dist_mid` quando a classe está ausente.
`interior_detail` usa `dist_near` por padrão. O addon troca a representação
das instâncias marcadas e com tag.

## Distâncias e cores

| Tag | Volta à malha ao chegar a | Volta à caixa ao ultrapassar |
| --- | ---: | ---: |
| `dist_near` | 5 m | 7 m |
| `dist_local` | 25 m | 32 m |
| `dist_mid` | 50 m | 60 m |
| `dist_away` | 100 m | 115 m |
| `dist_remote` | 200 m | 220 m |

O alcance é quadrado no plano X/Z e mede a distância até os limites da
instância. O metadado opcional `stream_bounds` aceita uma `AABB` em
coordenadas locais. Quando ele está ausente, o addon usa os limites da
geometria. Um valor personalizado em `stream_class` usa o alcance padrão
de 45 m.

Cada caixa compartilha uma malha de oito vértices e doze triângulos.
A cor-base identifica a classe. Dentro da classe, o brilho varia em
cinco níveis estáveis, calculados pelo caminho da instância na cena.
As caixas são gizmos do editor e a cena salva conserva as instâncias
originais.

## Recursos no editor e no jogo

O Godot abre as instâncias nativas e seus recursos ao carregar a cena
no editor. A caixa reduz a geometria desenhada ao longe e o addon oculta
as luzes do prefab nesse estado. O custo inicial de instanciar os recursos
continua sujeito ao tamanho e à quantidade dos prefabs.

No jogo, **Load as Placeholder** produz um `InstancePlaceholder`. O
gerenciador de carregamento do jogo decide quando criar essa instância.
[Documentação do Godot](https://docs.godotengine.org/en/4.7/classes/class_instanceplaceholder.html)

## Atualização da versão 0.3

Nas cenas que usavam `ProximityPlacement3D`, instancie o prefab registrado
em **Scene Path** e transfira a transformação e os metadados da colocação.
Marque **Load as Placeholder** e confira a classe de distância. O fluxo
0.4 usa a instância e suas tags. O nó `ProximityPreview3D` e o índice
`proximity_prefabs.json` faziam parte da configuração 0.3.

## Teste

Com Godot no PATH, execute o teste em um projeto temporário.

```bash
python3 tests/run_editor_test.py
```

No Linux sem desktop, use uma tela virtual.

```bash
xvfb-run -a python3 tests/run_editor_test.py
```

O teste cobre instâncias nativas, classes de distância, a troca visual
na fronteira, as cores e o arquivo salvo.
