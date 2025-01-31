/*******************************************************************************
 * Copyright (c) 2022 - 2024 NVIDIA Corporation & Affiliates.                  *
 * All rights reserved.                                                        *
 *                                                                             *
 * This source code and the accompanying materials are made available under    *
 * the terms of the Apache License 2.0 which accompanies this distribution.    *
 ******************************************************************************/

#include "RestClient.h"
#include "Logger.h"
#include <cpr/cpr.h>
#include <zlib.h>

namespace cudaq {
constexpr long validHttpCode = 205;

/// Decompress GZIP data. Throws an exception on error.
std::string decompress_gzip(const std::string &data) {
  if (data.empty())
    return data;

  std::string decompressed;
  z_stream zs{};
  zs.avail_in = data.size();
  zs.next_in = reinterpret_cast<Bytef *>(const_cast<char *>(data.data()));

  // Add 16 to indicate gzip decoding
  if (inflateInit2(&zs, 16 + MAX_WBITS) != Z_OK)
    throw std::runtime_error("inflateInit2 failed while decompressing.");

  // Uncompress 32 KB at a time
  constexpr auto buffSize = 32678;
  auto buffer = std::make_unique<char[]>(buffSize);
  int ret;
  do {
    zs.avail_out = buffSize;
    zs.next_out = reinterpret_cast<Bytef *>(buffer.get());
    ret = inflate(&zs, 0);
    if (decompressed.size() < zs.total_out)
      decompressed.append(buffer.get(), zs.total_out - decompressed.size());
  } while (ret == Z_OK);

  inflateEnd(&zs);

  if (ret != Z_STREAM_END)
    throw std::runtime_error("Exception during zlib decompression");

  return decompressed;
}

nlohmann::json RestClient::post(const std::string_view remoteUrl,
                                const std::string_view path,
                                nlohmann::json &post,
                                std::map<std::string, std::string> &headers,
                                bool enableLogging, bool enableSsl) {
  if (headers.empty())
    headers.insert(std::make_pair("Content-type", "application/json"));

  cpr::Header cprHeaders;
  for (auto &kv : headers)
    cprHeaders.insert({kv.first, kv.second});

  // Allow caller to disable logging for things like passwords/tokens
  if (enableLogging)
    cudaq::info("Posting to {}/{} with data = {}", remoteUrl, path,
                post.dump());

  auto actualPath = std::string(remoteUrl) + std::string(path);
  auto r = cpr::Post(cpr::Url{actualPath}, cpr::Body(post.dump()), cprHeaders,
                     cpr::VerifySsl(enableSsl));

  if (r.status_code > validHttpCode || r.status_code == 0)
    throw std::runtime_error("HTTP POST Error - status code " +
                             std::to_string(r.status_code) + ": " +
                             r.error.message + ": " + r.text);

  return nlohmann::json::parse(r.text);
}

void RestClient::put(const std::string_view remoteUrl,
                     const std::string_view path, nlohmann::json &putData,
                     std::map<std::string, std::string> &headers,
                     bool enableLogging, bool enableSsl) {
  if (headers.empty())
    headers.insert(std::make_pair("Content-type", "application/json"));

  cpr::Header cprHeaders;
  for (auto &kv : headers)
    cprHeaders.insert({kv.first, kv.second});

  // Allow caller to disable logging for things like passwords/tokens
  if (enableLogging)
    cudaq::info("Putting to {}/{} with data = {}", remoteUrl, path,
                putData.dump());

  auto actualPath = std::string(remoteUrl) + std::string(path);
  auto r = cpr::Put(cpr::Url{actualPath}, cpr::Body(putData.dump()), cprHeaders,
                    cpr::VerifySsl(enableSsl));

  if (r.status_code > validHttpCode || r.status_code == 0)
    throw std::runtime_error("HTTP PUT Error - status code " +
                             std::to_string(r.status_code) + ": " +
                             r.error.message + ": " + r.text);
}

nlohmann::json RestClient::get(const std::string_view remoteUrl,
                               const std::string_view path,
                               std::map<std::string, std::string> &headers,
                               bool enableSsl) {
  if (headers.empty())
    headers.insert(std::make_pair("Content-type", "application/json"));

  cpr::Header cprHeaders;
  for (auto &kv : headers)
    cprHeaders.insert({kv.first, kv.second});

  cpr::Parameters cprParams;
  auto actualPath = std::string(remoteUrl) + std::string(path);
  auto r = cpr::Get(cpr::Url{actualPath}, cprHeaders, cprParams,
                    cpr::VerifySsl(enableSsl));

  if (r.status_code > validHttpCode || r.status_code == 0)
    throw std::runtime_error("HTTP GET Error - status code " +
                             std::to_string(r.status_code) + ": " +
                             r.error.message + ": " + r.text);

  // cpr used to do this automatically but no longer does as of PR #1010
  if (r.header["Content-Encoding"] == "gzip") {
    auto tmp = decompress_gzip(r.text);
    r.text = tmp;
  }
  return nlohmann::json::parse(r.text);
}

void RestClient::del(const std::string_view remoteUrl,
                     const std::string_view path,
                     std::map<std::string, std::string> &headers,
                     bool enableLogging, bool enableSsl) {
  cpr::Header cprHeaders;
  for (auto &kv : headers)
    cprHeaders.insert({kv.first, kv.second});

  cpr::Parameters cprParams;
  auto actualPath = std::string(remoteUrl) + std::string(path);
  if (enableLogging)
    cudaq::info("Delete resource at path {}/{}", remoteUrl, path);
  auto r = cpr::Delete(cpr::Url{actualPath}, cprHeaders, cprParams,
                       cpr::VerifySsl(enableSsl));

  if (r.status_code > validHttpCode || r.status_code == 0)
    throw std::runtime_error("HTTP DELETE Error - status code " +
                             std::to_string(r.status_code) + ": " +
                             r.error.message + ": " + r.text);
}

void RestClient::download(const std::string_view remoteUrl,
                          const std::string &filePath, bool enableLogging,
                          bool enableSsl) {
  auto r = cpr::Get(cpr::Url{std::string(remoteUrl)}, cpr::Header{},
                    cpr::Parameters{}, cpr::VerifySsl(enableSsl));

  if (r.status_code > validHttpCode || r.status_code == 0)
    throw std::runtime_error("HTTP Download Error - status code " +
                             std::to_string(r.status_code) + ": " +
                             r.error.message + ": " + r.text);

  if (enableLogging)
    cudaq::info("Downloading {} bytes from {} to file {}", r.text.size(),
                remoteUrl, filePath);

  try {
    // Write the downloaded content to file.
    std::ofstream outfile(filePath, std::ofstream::binary | std::ios::out);
    outfile.write(r.text.c_str(), r.text.size());
    outfile.close();
  } catch (std::exception &e) {
    // Rethrow it with a descriptive message
    throw std::runtime_error(fmt::format(
        "Failed to write downloaded contents to file {}. Exception: {}.",
        filePath, e.what()));
  }
}
} // namespace cudaq
