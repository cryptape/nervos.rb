# frozen_string_literal: true

require "ciri/utils"
require "ciri/crypto"

module AppChain
  class TransactionSigner
    class << self
      # sign transaction
      #
      # @param transaction [AppChain::Transaction]
      # @param private_key [String]
      def encode(transaction, private_key)
        tx = AppChain::Protos::Transaction.new

        to = AppChain::Utils.remove_hex_prefix(transaction.to)&.downcase

        tx.nonce = transaction.nonce
        tx.quota = transaction.quota
        tx.data = AppChain::Utils.to_bytes(transaction.data)
        tx.value = hex_to_bytes(transaction.value)
        tx.version = transaction.version
        tx.valid_until_block = transaction.valid_until_block

        if transaction.version.zero?
          tx.to = to unless to.nil?
          tx.chain_id = transaction.chain_id
        elsif transaction.version == 1
          tx.to_v1 = Utils.to_bytes(to) unless to.nil?
          tx.chain_id_v1 = hex_to_bytes(transaction.chain_id)
        end

        encoded_tx = Protos::Transaction.encode(tx)

        private_key_bytes = AppChain::Utils.to_bytes(private_key)

        protobuf_hash = Utils.keccak256(encoded_tx)

        signature = Ciri::Crypto.ecdsa_signature(private_key_bytes, protobuf_hash).signature

        unverified_tx = Protos::UnverifiedTransaction.new(transaction: tx, signature: signature)

        encoded_unverified_tx = Protos::UnverifiedTransaction.encode(unverified_tx)

        AppChain::Utils.from_bytes(encoded_unverified_tx)
      end

      # unsign transaction
      #
      # @param tx_content [String] hex string
      def simple_decode(tx_content)
        content_bytes = AppChain::Utils.to_bytes(tx_content)
        unverified_transaction = Protos::UnverifiedTransaction.decode(content_bytes)

        signature = unverified_transaction["signature"]

        transaction = unverified_transaction["transaction"]
        msg = Protos::Transaction.encode(transaction)
        msg_hash = AppChain::Utils.keccak256(msg)
        pubkey = Ciri::Crypto.ecdsa_recover(msg_hash, signature)
        pubkey_hex = Utils.from_bytes(pubkey[1..-1])

        from_address = Utils.keccak256(pubkey[1..-1])[-20..-1]
        from_address_hex = Utils.from_bytes(from_address)

        sender = {
          address: from_address_hex,
          public_key: pubkey_hex
        }

        {
          unverified_transaction: unverified_transaction.to_h,
          sender: sender
        }
      end

      # decode and support forks
      # @param tx_content [String] hex string
      # @return [Hash]
      def decode(tx_content)
        data = simple_decode(tx_content)
        utx = data[:unverified_transaction]
        tx = utx[:transaction]
        version = tx[:version]

        if version.zero?
          tx.delete(:to_v1)
          tx.delete(:chain_id_v1)
        elsif version == 1
          tx[:to] = tx.delete(:to_v1)
          tx[:chain_id] = tx.delete(:chain_id_v1)
        else
          raise Transaction::VersionError, "transaction version error, expected 0 or 1, got #{version}"
        end

        data
      end

      private

      # @param value [String] hex string with or without `0x` prefix
      # @param length [Integer] length, default is 64
      # @return [String] byte code string
      def hex_to_bytes(value, length = 64)
        AppChain::Utils.to_bytes(AppChain::Utils.remove_hex_prefix(value).rjust(length, "0"))
      end
    end
  end
end
