/*
 ============================================================================
 Name        : hev-main.h
 Author      : hev <r@hev.cc>
 Copyright   : Copyright (c) 2019 - 2023 hev
 Description : Main
 ============================================================================
 */

#ifndef __HEV_MAIN_H__
#define __HEV_MAIN_H__

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int hev_socks5_tunnel_main (const char *config_path, int tun_fd);

int hev_socks5_tunnel_main_from_file (const char *config_path, int tun_fd);

int hev_socks5_tunnel_main_from_str (const unsigned char *config_str,
                                     unsigned int config_len, int tun_fd);

void hev_socks5_tunnel_quit (void);

void hev_socks5_tunnel_stats (size_t *tx_packets, size_t *tx_bytes,
                              size_t *rx_packets, size_t *rx_bytes);

#ifdef __cplusplus
}
#endif

#endif
