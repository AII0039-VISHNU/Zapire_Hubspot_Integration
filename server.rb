require 'stripe'
require 'sinatra'
require 'net/http'
require 'uri'
require 'json'

Stripe.api_key = 'sk_test_51Qx2E1GH9aDXudBCg9IUgu3g7mc6ejwn0dAhsdPxvdx9WlTN4LQlZGs5Wy3vTiSnneXae86MHeb2U7ZeraXhQ1bg00UCZy21Pi'

set :static, true
set :port, 4242

YOUR_DOMAIN = 'http://localhost:4242'
ZAPIER_WEBHOOK_URL = 'https://hooks.zapier.com/hooks/catch/21763314/2q4fmaw/'

post '/create-checkout-session' do
  content_type 'application/json'
  request_data = JSON.parse(request.body.read) rescue {}
  email = request_data['email']

  if email.nil? || email.strip.empty?
    puts "Error: No email provided in checkout request"
    status 400
    return { error: "Email is required to start checkout" }.to_json
  end

  current_time = Time.now
  expires_at = current_time.to_i + (30 * 60)

  puts "Checkout Started - Email: #{email}, Expires At: #{Time.at(expires_at)}"

  begin
    session = Stripe::Checkout::Session.create({
      payment_method_types: ['card'],
      line_items: [{
        price: "price_1Qx3tyGH9aDXudBCf3WXvB89",
        quantity: 1,
      }],
      mode: 'payment',
      expires_at: expires_at,
      success_url: "#{YOUR_DOMAIN}/success?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "#{YOUR_DOMAIN}/cancel.html",
      customer_email: email,  
      metadata: { email: email, product_id: "12345" } 
    })

    zapier_data = { email_checkout: email, event: "checkout_started" }
    zapier_response = send_to_zapier(zapier_data)

    puts "Zapier Response for Checkout Started: #{zapier_response}"

    { id: session.id, zapier_response: zapier_response }.to_json
  rescue Stripe::StripeError => e
    status 500
    { error: e.message }.to_json
  end
end

post '/stripe-webhook' do
  payload = request.body.read
  sig_header = request.env['HTTP_STRIPE_SIGNATURE']
  endpoint_secret = 'whsec_Yu2uym5fqdmyamEcynHmcEOFqhN2RbkG'

  event = nil
  begin
    event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
  rescue JSON::ParserError => e
    status 400
    return { error: "Webhook error: #{e.message}" }.to_json
  rescue Stripe::SignatureVerificationError => e
    status 400
    return { error: "Webhook signature verification failed: #{e.message}" }.to_json
  end

  zapier_response = nil
  case event['type']
  when 'checkout.session.completed'
    session = event['data']['object']
    
    email = session.dig('customer_email') || 
            session.dig('customer_details', 'email') || 
            session.dig('metadata', 'email')

    puts "✅ Payment Success - Email: #{email}"
    
    zapier_response = send_to_zapier({
      session_id: session['id'],
      email_success: email,
      status: "completed"
    })
  when 'checkout.session.expired'
    session = event['data']['object']
    
    email = session.dig('customer_email') || 
            session.dig('customer_details', 'email') || 
            session.dig('metadata', 'email')

    puts "⚠️ Payment Expired - Email: #{email}"
    
    zapier_response = send_to_zapier({
      session_id: session['id'],
      email_expired: email,
      status: "expired"
    })
  else
    puts "Unhandled event type: #{event['type']}"
  end

  { status: "success", zapier_response: zapier_response }.to_json
end



def send_to_zapier(data)
  uri = URI.parse(ZAPIER_WEBHOOK_URL)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Post.new(uri.path, { 'Content-Type' => 'application/json' })
  request.body = data.to_json
  response = http.request(request)
  
  puts "Zapier Response: #{response.body}"
  response.body
rescue StandardError => e
  puts "Error sending to Zapier: #{e.message}"
  { error: e.message }.to_json
end




