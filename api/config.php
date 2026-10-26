<?php
return [
    'db_host' => '127.0.0.1',
    'db_name' => 'nama_puducherry',
    'db_user' => 'root',
    'db_pass' => '',
    'admin_key' => 'change-admin-key',
    'nearby_km' => 5,
    // Service areas: pickup and drop must each be within radius_km of one of these centres.
    // Trips between areas (e.g. Puducherry -> Villupuram) are allowed.
    'areas' => [
        ['name' => 'Puducherry', 'lat' => 11.9416, 'lng' => 79.8083, 'radius_km' => 15],
        ['name' => 'Cuddalore',  'lat' => 11.7480, 'lng' => 79.7714, 'radius_km' => 12],
        ['name' => 'Villupuram', 'lat' => 11.9401, 'lng' => 79.4861, 'radius_km' => 12],
        ['name' => 'Tindivanam', 'lat' => 12.2417, 'lng' => 79.6560, 'radius_km' => 10],
    ],
    'rates' => [
        'auto'      => ['base' => 30, 'perKm' => 12],
        'hatchback' => ['base' => 50, 'perKm' => 14],
        'sedan'     => ['base' => 60, 'perKm' => 16],
        'suv'       => ['base' => 80, 'perKm' => 20],
    ],
];
