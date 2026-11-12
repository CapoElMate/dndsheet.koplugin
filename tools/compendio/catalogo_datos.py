# SPDX-License-Identifier: AGPL-3.0-or-later
"""Datos de catálogo de conjuros de XGE (nombre, nivel, escuela, clases, ritual, concentración).

Son datos de reglas (hechos de catálogo), no texto del libro. catalogo.py verifica que cada nombre
figure en el PDF del usuario y compara clases/nivel/escuela con lo que se lee del libro; imprime las
divergencias para revisarlas a mano. Formato: "Nombre|nivel|Escuela|Clases separadas por coma|flags"
(flags: r = ritual, c = concentración).
"""
XGE_SPELLS = """
Control Flames|0|Transmutation|Druid,Sorcerer,Wizard|
Create Bonfire|0|Conjuration|Druid,Sorcerer,Warlock,Wizard|c
Frostbite|0|Evocation|Druid,Sorcerer,Warlock,Wizard|
Gust|0|Transmutation|Druid,Sorcerer,Wizard|
Infestation|0|Conjuration|Druid,Sorcerer,Warlock,Wizard|
Magic Stone|0|Transmutation|Druid,Warlock|
Mold Earth|0|Transmutation|Druid,Sorcerer,Wizard|
Primal Savagery|0|Transmutation|Druid|
Shape Water|0|Transmutation|Druid,Sorcerer,Wizard|
Thunderclap|0|Evocation|Bard,Druid,Sorcerer,Warlock,Wizard|
Toll the Dead|0|Necromancy|Cleric,Warlock,Wizard|
Word of Radiance|0|Evocation|Cleric|
Absorb Elements|1|Abjuration|Druid,Ranger,Sorcerer,Wizard|
Beast Bond|1|Divination|Druid,Ranger|c
Catapult|1|Transmutation|Sorcerer,Wizard|
Cause Fear|1|Necromancy|Warlock,Wizard|c
Ceremony|1|Abjuration|Cleric,Paladin|r
Chaos Bolt|1|Evocation|Sorcerer|
Earth Tremor|1|Evocation|Bard,Druid,Sorcerer,Wizard|
Ice Knife|1|Conjuration|Druid,Sorcerer,Wizard|
Snare|1|Abjuration|Druid,Ranger,Wizard|
Zephyr Strike|1|Transmutation|Ranger|c
Aganazzar's Scorcher|2|Evocation|Sorcerer,Wizard|
Dragon's Breath|2|Transmutation|Sorcerer,Wizard|c
Dust Devil|2|Conjuration|Druid,Sorcerer,Wizard|c
Earthbind|2|Transmutation|Druid,Sorcerer,Warlock,Wizard|c
Healing Spirit|2|Conjuration|Druid,Ranger|c
Maximilian's Earthen Grasp|2|Transmutation|Sorcerer,Wizard|c
Mind Spike|2|Divination|Sorcerer,Warlock,Wizard|c
Pyrotechnics|2|Transmutation|Bard,Sorcerer,Wizard|
Shadow Blade|2|Illusion|Sorcerer,Warlock,Wizard|c
Skywrite|2|Transmutation|Bard,Druid,Sorcerer,Wizard|rc
Snilloc's Snowball Swarm|2|Evocation|Sorcerer,Wizard|
Warding Wind|2|Evocation|Bard,Druid,Sorcerer,Wizard|c
Catnap|3|Enchantment|Bard,Sorcerer,Wizard|
Enemies Abound|3|Enchantment|Bard,Sorcerer,Warlock,Wizard|c
Erupting Earth|3|Transmutation|Druid,Sorcerer,Wizard|
Flame Arrows|3|Transmutation|Druid,Ranger,Sorcerer,Wizard|c
Life Transference|3|Necromancy|Cleric,Wizard|
Melf's Minute Meteors|3|Evocation|Sorcerer,Wizard|c
Summon Lesser Demons|3|Conjuration|Warlock,Wizard|c
Thunder Step|3|Conjuration|Sorcerer,Warlock,Wizard|
Tidal Wave|3|Conjuration|Druid,Sorcerer,Wizard|
Tiny Servant|3|Transmutation|Wizard|
Wall of Sand|3|Evocation|Wizard|c
Wall of Water|3|Evocation|Druid,Sorcerer,Wizard|c
Charm Monster|4|Enchantment|Bard,Druid,Sorcerer,Warlock,Wizard|
Elemental Bane|4|Transmutation|Druid,Warlock,Wizard|c
Guardian of Nature|4|Transmutation|Druid,Ranger|c
Shadow of Moil|4|Necromancy|Warlock|c
Sickening Radiance|4|Evocation|Sorcerer,Warlock,Wizard|c
Storm Sphere|4|Evocation|Sorcerer,Wizard|c
Summon Greater Demon|4|Conjuration|Warlock,Wizard|c
Vitriolic Sphere|4|Evocation|Sorcerer,Wizard|
Watery Sphere|4|Conjuration|Druid,Sorcerer,Wizard|c
Bones of the Earth|6|Transmutation|Druid|
Control Winds|5|Transmutation|Druid,Sorcerer,Wizard|c
Create Homunculus|6|Transmutation|Wizard|
Danse Macabre|5|Necromancy|Warlock,Wizard|c
Dawn|5|Evocation|Cleric,Wizard|c
Enervation|5|Necromancy|Sorcerer,Warlock,Wizard|c
Far Step|5|Conjuration|Sorcerer,Warlock,Wizard|c
Holy Weapon|5|Evocation|Cleric,Paladin|c
Immolation|5|Evocation|Sorcerer,Wizard|c
Infernal Calling|5|Conjuration|Warlock,Wizard|c
Maelstrom|5|Evocation|Druid|c
Negative Energy Flood|5|Necromancy|Warlock,Wizard|
Skill Empowerment|5|Transmutation|Bard,Sorcerer,Wizard|
Steel Wind Strike|5|Conjuration|Ranger,Wizard|
Synaptic Static|5|Enchantment|Bard,Sorcerer,Warlock,Wizard|
Transmute Rock|5|Transmutation|Druid,Wizard|
Wall of Light|5|Evocation|Sorcerer,Warlock,Wizard|c
Wrath of Nature|5|Evocation|Druid,Ranger|c
Investiture of Flame|6|Transmutation|Druid,Sorcerer,Warlock,Wizard|c
Investiture of Ice|6|Transmutation|Druid,Sorcerer,Warlock,Wizard|c
Investiture of Stone|6|Transmutation|Druid,Sorcerer,Warlock,Wizard|c
Investiture of Wind|6|Transmutation|Druid,Sorcerer,Warlock,Wizard|c
Mental Prison|6|Illusion|Sorcerer,Warlock,Wizard|c
Primordial Ward|6|Abjuration|Druid|c
Scatter|6|Conjuration|Sorcerer,Warlock,Wizard|
Soul Cage|6|Necromancy|Sorcerer,Warlock,Wizard|
Tenser's Transformation|6|Transmutation|Wizard|c
Crown of Stars|7|Evocation|Sorcerer,Warlock,Wizard|
Power Word Pain|7|Enchantment|Sorcerer,Warlock,Wizard|
Temple of the Gods|7|Conjuration|Cleric|
Whirlwind|7|Evocation|Druid,Sorcerer,Wizard|c
Abi-Dalzim's Horrid Wilting|8|Necromancy|Sorcerer,Wizard|
Illusory Dragon|8|Illusion|Wizard|c
Maddening Darkness|8|Evocation|Warlock,Wizard|c
Mighty Fortress|8|Conjuration|Wizard|
Invulnerability|9|Abjuration|Wizard|c
Mass Polymorph|9|Transmutation|Bard,Sorcerer,Wizard|c
Psychic Scream|9|Enchantment|Bard,Sorcerer,Warlock,Wizard|
"""
